# upload-save.ps1 -- upload a locally crafted Factorio save (and
# optionally a mods folder) to the k3s Factorio server.
#
# Companion: ../FACTORIO.md. Run from PowerShell on the gaming PC,
# with your usual kubeconfig (KUBECONFIG / ~/.kube/config pointing at
# the homelab cluster) and kubectl on PATH.
#
#   .\upload-save.ps1 -Save "$env:APPDATA\Factorio\saves\scribnet-space-age.zip" -CleanThrowaway
#   .\upload-save.ps1 -Save <save.zip> -Mods "$env:APPDATA\Factorio\mods"
#
# How it works (no black boxes): validates the zip is a real Factorio
# save -> scales the server to 0 -> starts a one-shot busybox helper
# pod mounting the SAME Longhorn PVC on the SAME node -> backs up
# every save currently in the PVC to /data/backups/upload-<timestamp>/
# -> only then optionally cleans throwaways and copies the new save
# in through the helper -> verifies the uploaded save is the
# NEWEST file in saves/ (LOAD_LATEST_SAVE=true keys on that) ->
# removes the helper -> scales the server back to 1.
# If verification fails the script STOPS with the server still at 0
# and the helper pod left running for inspection -- it never starts
# the wrong world silently.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Save,
    [string]$Mods,
    [switch]$CleanThrowaway,
    [string]$Namespace = "factorio",
    [string]$StatefulSet = "factorio",
    [string]$Claim = "factorio-data-factorio-0",
    [string]$HelperPod = "factorio-upload"
)

$ErrorActionPreference = "Stop"

function Invoke-Kubectl {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & kubectl @Args
    if ($LASTEXITCODE -ne 0) { throw "kubectl $($Args -join ' ') failed (exit $LASTEXITCODE)" }
}

# --- 1. Validate the save locally -----------------------------------
if (-not (Test-Path $Save)) { throw "Save not found: $Save" }
$Save = (Resolve-Path $Save).Path
$saveName = Split-Path $Save -Leaf
if ($saveName -notmatch '\.zip$') { throw "Factorio saves are .zip files: $saveName" }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Save)
try {
    $hasLevel = $zip.Entries | Where-Object { $_.FullName -match 'level\.dat' } | Select-Object -First 1
    if (-not $hasLevel) { throw "$saveName contains no level.dat entry -- not a Factorio save zip." }
} finally { $zip.Dispose() }
Write-Host "Save validated: $saveName"

if ($Mods) {
    if (-not (Test-Path $Mods)) { throw "Mods folder not found: $Mods" }
    $modZips = Get-ChildItem -Path $Mods -Filter *.zip -File
    Write-Host "Mods to upload: $($modZips.Count) zip(s) from $Mods"
}

# --- 2. Cluster preflight -------------------------------------------
Invoke-Kubectl -Args @("cluster-info")
Invoke-Kubectl -Args @("-n", $Namespace, "get", "statefulset", $StatefulSet)

# --- 3. Stop the server (no autosave may race the upload) -----------
Write-Host "Scaling $StatefulSet to 0..."
Invoke-Kubectl -Args @("-n", $Namespace, "scale", "statefulset", $StatefulSet, "--replicas=0")
& kubectl -n $Namespace wait --for=delete "pod/$StatefulSet-0" --timeout=120s 2>$null
# (wait errors are fine here -- the pod may already be gone)

# --- 4. Helper pod on the same node, same PVC ------------------------
# The helper is created from a manifest FILE, never from
# `kubectl run --overrides <json>`: PowerShell 5.1 strips the inner
# double quotes from a no-space JSON argument handed to a native
# exe, and kubectl then rejects it ("Invalid JSON Patch" -- hit
# live on the 2026-10-25 test run). A file has no quoting to strip.
$helperYaml = Join-Path $env:TEMP "$HelperPod-pod.yaml"
$podYaml = @(
    'apiVersion: v1',
    'kind: Pod',
    'metadata:',
    "  name: $HelperPod",
    'spec:',
    '  nodeSelector:',
    '    example.com/game-server: "true"',
    '  restartPolicy: Never',
    '  containers:',
    "    - name: $HelperPod",
    '      image: busybox:1.36',
    '      command: ["sleep", "3600"]',
    '      volumeMounts:',
    '        - name: data',
    '          mountPath: /data',
    '  volumes:',
    '    - name: data',
    '      persistentVolumeClaim:',
    "        claimName: $Claim"
) -join "`n"
[IO.File]::WriteAllText($helperYaml, $podYaml, [Text.Encoding]::ASCII)

# Clean a leftover helper from a previous failed run.
& kubectl -n $Namespace delete pod $HelperPod --ignore-not-found 2>$null | Out-Null
Write-Host "Starting helper pod ($HelperPod)..."
Invoke-Kubectl -Args @("-n", $Namespace, "apply", "-f", $helperYaml)
Invoke-Kubectl -Args @("-n", $Namespace, "wait", "--for=condition=Ready", "pod/$HelperPod", "--timeout=120s")
Invoke-Kubectl -Args @("-n", $Namespace, "exec", $HelperPod, "--", "mkdir", "-p", "/data/saves", "/data/mods")

# --- 5. Back up the current saves (before anything is deleted) -----
# Every .zip currently in /data/saves is copied to a timestamped
# folder OUTSIDE saves/ -- /data/backups/upload-<timestamp>/ -- on
# the same PVC, so an upload can never destroy the previous world
# without a copy sitting next to it. This is a pre-change safety
# net on the same volume, NOT the off-box backup layer (that is the
# Longhorn/GFS stage). Skips cleanly when saves/ holds no zips.
# The listing must exit 0 even when the glob matches nothing --
# an empty saves/ is a NORMAL state (e.g. right after a cleanup).
# With $ErrorActionPreference = Stop, PowerShell 5.1 turns a
# native command's nonzero exit through redirected stderr into a
# terminating NativeCommandError (hit live on the 2026-10-25
# rerun, at exactly this line), so the in-pod command ends in
# "exit 0" and the outer stderr redirect is gone.
$currentZips = & kubectl -n $Namespace exec $HelperPod -- sh -c "ls -1 /data/saves/*.zip 2>/dev/null; exit 0"
if ($currentZips) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = "/data/backups/upload-$stamp"
    Write-Host "Backing up $($currentZips.Count) existing save(s) to $backupDir ..."
    Invoke-Kubectl -Args @("-n", $Namespace, "exec", $HelperPod, "--", "mkdir", "-p", $backupDir)
    foreach ($z in $currentZips) {
        Invoke-Kubectl -Args @("-n", $Namespace, "exec", $HelperPod, "--", "cp", "-a", $z.Trim(), "$backupDir/")
    }
    $backedUp = & kubectl -n $Namespace exec $HelperPod -- ls -1 $backupDir
    Write-Host "Backup contents:"
    $backedUp | ForEach-Object { Write-Host "  $_" }
    if ($backedUp.Count -ne $currentZips.Count) { throw "Backup verification failed: $($backedUp.Count) of $($currentZips.Count) saves copied. Server left at 0 replicas; helper pod left running." }
} else {
    Write-Host "No existing saves in the PVC -- nothing to back up."
}

# --- 6. Optional: remove the first-boot throwaway saves -------------
if ($CleanThrowaway) {
    $existing = & kubectl -n $Namespace exec $HelperPod -- ls -1 /data/saves
    $throwaway = $existing | Where-Object { $_ -match '^_autosave.*\.zip$' -and $_ -ne $saveName }
    if ($throwaway) {
        Write-Host "Throwaway saves that -CleanThrowaway will delete:"
        $throwaway | ForEach-Object { Write-Host "  $_" }
        $answer = Read-Host "Delete these $($throwaway.Count) file(s)? Type yes"
        if ($answer -ne "yes") { throw "Aborted at cleanup. Server is still at 0 replicas; helper pod left running. Delete it with: kubectl -n $Namespace delete pod $HelperPod" }
        foreach ($f in $throwaway) {
            Invoke-Kubectl -Args @("-n", $Namespace, "exec", $HelperPod, "--", "rm", "-f", "/data/saves/$f")
        }
    } else {
        Write-Host "No throwaway _autosave zips found -- nothing to clean."
    }
}

# --- 7. Copy the save (and mods) in ----------------------------------
# kubectl cp parses "pod:path" by colon, so a Windows drive-letter
# path (C:\...) looks REMOTE to it and the copy is rejected with
# "one of src or dest must be a local file specification" (hit live
# on the 2026-10-25 test run). Copies therefore run from inside the
# source folder with a relative .\ path, and the pod side is plain
# "pod:path" (the -n flag already carries the namespace).
Write-Host "Uploading $saveName ..."
Push-Location (Split-Path $Save)
try {
    Invoke-Kubectl -Args @("-n", $Namespace, "cp", ".\$saveName", "${HelperPod}:/data/saves/$saveName")
} finally { Pop-Location }
if ($Mods) {
    Push-Location $Mods
    try {
        foreach ($m in $modZips) {
            Write-Host "Uploading mod $($m.Name) ..."
            Invoke-Kubectl -Args @("-n", $Namespace, "cp", ".\$($m.Name)", "${HelperPod}:/data/mods/$($m.Name)")
        }
    } finally { Pop-Location }
}

# --- 8. Verify: the uploaded save must be the newest -----------------
# Scoped Continue so a nonzero exit reaches the check below
# instead of terminating as a NativeCommandError (see step 5).
$ErrorActionPreference = "Continue"
$listing = & kubectl -n $Namespace exec $HelperPod -- sh -c "ls -t /data/saves/*.zip"
$listExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($listExit -ne 0 -or -not $listing) {
    throw "Could not list saves in the PVC. Server left at 0 replicas; helper pod left running for inspection."
}
$newest = Split-Path ($listing | Select-Object -First 1).Trim() -Leaf
Write-Host "Saves in PVC, newest first:"
$listing | ForEach-Object { Write-Host "  $_" }
if ($newest -ne $saveName) {
    throw "Newest save is '$newest', not '$saveName'. Server left at 0 replicas on purpose -- fix the ordering (re-upload, or remove the newer file via the helper pod) before scaling back up."
}

# --- 9. Remove helper, start the server ------------------------------
Invoke-Kubectl -Args @("-n", $Namespace, "delete", "pod", $HelperPod, "--wait=true")
Remove-Item $helperYaml -ErrorAction SilentlyContinue
Write-Host "Scaling $StatefulSet back to 1..."
Invoke-Kubectl -Args @("-n", $Namespace, "scale", "statefulset", $StatefulSet, "--replicas=1")
Invoke-Kubectl -Args @("-n", $Namespace, "rollout", "status", "statefulset/$StatefulSet", "--timeout=180s")

Write-Host ""
Write-Host "Done. Prove it with the log + a real join:"
Write-Host "  kubectl -n $Namespace logs statefulset/$StatefulSet -f   # expect your save loading"
Write-Host "  In game: Multiplayer > Connect to address > <agent-lan-ip>:34197 (LAN, first pass)"
