# configure-server.ps1 -- set the Factorio game password, the
# server name/description, and the admin/whitelist name lists on
# the k3s server's PVC, interactively.
#
# Companion: ../FACTORIO.md. Run from PowerShell on the gaming PC.
# Built for the LIVE deploy; rehearsed first on the test instance.
#
#   .\configure-server.ps1                # password + name + admins (+ whitelist)
#   .\configure-server.ps1 -SkipWhitelist # password + name + admins only
#   .\configure-server.ps1 -ServerName "ScribNet Space Age" -ServerDescription "Dad-mode co-op"
#
# Security model (why it is built this way):
# - The game password is typed at a hidden prompt (twice, to catch
#   typos), held in memory, and written into a LOCAL temp copy of
#   server-settings.json that is deleted when the script exits.
# - It is NEVER a command-line argument, an environment variable, a
#   manifest value, or anything sent to chat/git. Its durable homes
#   are Dashlane and the PVC -- nowhere else.
# - Verification prints the password's LENGTH and the admin list,
#   never the password itself.
# - Admins and whitelist are the same names (flat trust model,
#   decided 2026-10-25): everyone invited is a game admin. The
#   whitelist is the access gate, so a name missing from the list
#   CANNOT join -- yours must be on it.
#
# Flow: prompt for password -> scale server to 0 -> busybox helper
# pod on the same PVC -> back up current settings (.bak) -> copy
# server-settings.json out, edit locally, copy back -> write
# server-adminlist.json (+ server-whitelist.json) -> verify ->
# helper removed -> scale back to 1.
# On any failure after the scale-down, the script stops with the
# server still at 0 and the helper pod left running, and prints the
# one command that puts the server back.
[CmdletBinding()]
param(
    [string]$ServerName,
    [string]$ServerDescription,
    [switch]$SkipWhitelist,
    [string]$Namespace = "factorio",
    [string]$StatefulSet = "factorio",
    [string]$Claim = "factorio-data-factorio-0",
    [string]$HelperPod = "factorio-config"
)

$ErrorActionPreference = "Stop"

function Invoke-Kubectl {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & kubectl @Args
    if ($LASTEXITCODE -ne 0) { throw "kubectl $($Args -join ' ') failed (exit $LASTEXITCODE)" }
}

function ConvertFrom-Secure {
    param([Security.SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# --- 1. Prompt for the game password (before any downtime) ----------
$secure1 = Read-Host "Game password for the server (input hidden)" -AsSecureString
$secure2 = Read-Host "Repeat the game password" -AsSecureString
$plain1 = ConvertFrom-Secure $secure1
$plain2 = ConvertFrom-Secure $secure2
if ([string]::IsNullOrEmpty($plain1)) { throw "Password must not be empty." }
if ($plain1 -ne $plain2) { throw "Passwords did not match -- nothing was changed." }
$plain2 = $null
Write-Host "Password captured in memory (length $($plain1.Length)). It will not be printed."

# --- 2. Cluster preflight -------------------------------------------
Invoke-Kubectl -Args @("cluster-info")
Invoke-Kubectl -Args @("-n", $Namespace, "get", "statefulset", $StatefulSet)

$tmp = Join-Path $env:TEMP ("factorio-config-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$scaledDown = $false

try {
    # --- 3. Stop the server (settings are read at boot) --------------
    Write-Host "Scaling $StatefulSet to 0..."
    Invoke-Kubectl -Args @("-n", $Namespace, "scale", "statefulset", $StatefulSet, "--replicas=0")
    $scaledDown = $true
    & kubectl -n $Namespace wait --for=delete "pod/$StatefulSet-0" --timeout=120s 2>$null

    # --- 4. Helper pod on the same node, same PVC --------------------
    # Manifest FILE, never `kubectl run --overrides <json>`:
    # PowerShell 5.1 strips inner double quotes from no-space JSON
    # arguments to native exes ("Invalid JSON Patch" -- see
    # upload-save.ps1, hit live 2026-10-25). A file has no quoting
    # to strip. The file lives in $tmp and is deleted in finally.
    $helperYaml = Join-Path $tmp "helper-pod.yaml"
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

    & kubectl -n $Namespace delete pod $HelperPod --ignore-not-found 2>$null | Out-Null
    Write-Host "Starting helper pod ($HelperPod)..."
    Invoke-Kubectl -Args @("-n", $Namespace, "apply", "-f", $helperYaml)
    Invoke-Kubectl -Args @("-n", $Namespace, "wait", "--for=condition=Ready", "pod/$HelperPod", "--timeout=120s")
    Invoke-Kubectl -Args @("-n", $Namespace, "exec", $HelperPod, "--", "mkdir", "-p", "/data/config")

    # --- 5. Back up current settings, copy them out ------------------
    # Tolerant call (the .bak copy may legitimately fail on a
    # never-booted volume): scoped Continue so a nonzero exit does
    # not terminate as a NativeCommandError under EAP=Stop -- the
    # PS 5.1 trap documented in upload-save.ps1 step 5.
    $ErrorActionPreference = "Continue"
    & kubectl -n $Namespace exec $HelperPod -- cp /data/config/server-settings.json /data/config/server-settings.json.bak 2>$null | Out-Null
    $ErrorActionPreference = "Stop"
    # kubectl cp misparses Windows drive-letter paths (the C: colon
    # makes a local path look like a pod:path spec) -- copies run
    # from inside $tmp with relative .\ names. See upload-save.ps1.
    $localSettings = Join-Path $tmp "server-settings.json"
    $localAdmins = Join-Path $tmp "server-adminlist.json"
    Push-Location $tmp
    try {
        Invoke-Kubectl -Args @("-n", $Namespace, "cp", "${HelperPod}:/data/config/server-settings.json", ".\server-settings.json")
        # Tolerant: no adminlist exists on a first run. Scoped
        # Continue for the same NativeCommandError reason as above.
        $ErrorActionPreference = "Continue"
        & kubectl -n $Namespace cp "${HelperPod}:/data/config/server-adminlist.json" ".\server-adminlist.json" 2>$null | Out-Null
        $ErrorActionPreference = "Stop"
    } finally { Pop-Location }
    if (-not (Test-Path $localSettings)) { throw "Could not copy server-settings.json out of the PVC." }
    $existingAdmins = @()
    if (Test-Path $localAdmins) {
        # Flatten to plain strings: @(ConvertFrom-Json ...) wraps the
        # parsed array as ONE element (array-of-array) -- the prompt
        # then prints "System.Object[]" and the keep-path would write
        # a NESTED list back. Caught live 2026-10-25 by the display
        # glitch before the keep-path ever ran.
        try {
            $parsedAdmins = Get-Content $localAdmins -Raw | ConvertFrom-Json
            $existingAdmins = @($parsedAdmins | ForEach-Object { "$_" })
        } catch { $existingAdmins = @() }
    }

    # --- 6. Admins: keep existing or replace --------------------------
    if ($existingAdmins.Count -gt 0) {
        Write-Host "Current admin list: $($existingAdmins -join ', ')"
        $typed = Read-Host "Admin Factorio usernames, comma-separated (Enter = keep current list)"
    } else {
        $typed = Read-Host "Admin Factorio usernames, comma-separated (include YOURSELF)"
    }
    if ([string]::IsNullOrWhiteSpace($typed)) {
        if ($existingAdmins.Count -eq 0) {
            throw "No admins given and none exist yet. Server left at 0; helper pod left running. Re-run the script, or restore with: kubectl -n $Namespace scale statefulset/$StatefulSet --replicas=1"
        }
        $admins = $existingAdmins
        Write-Host "Keeping current admin list."
    } else {
        $admins = @($typed -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    if ($admins.Count -eq 0) { throw "Admin list is empty -- refusing to write an empty list." }
    Write-Host "Admins (= whitelist unless -SkipWhitelist): $($admins -join ', ')"

    # --- 7. Edit settings locally, write the lists --------------------
    $settings = Get-Content $localSettings -Raw | ConvertFrom-Json
    if (-not $settings.PSObject.Properties["game_password"]) {
        $settings | Add-Member -NotePropertyName "game_password" -NotePropertyValue ""
    }
    $settings.game_password = $plain1
    # Server name + description: what the client's Continue button
    # and the server browser display. Params win; otherwise prompt
    # with the current value as the default (Enter keeps it). The
    # image's first-boot settings carry placeholder text here
    # ("Name of the game as it will appear in the server browser"),
    # so set a real name at deploy time.
    foreach ($field in @("name", "description")) {
        if (-not $settings.PSObject.Properties[$field]) {
            $settings | Add-Member -NotePropertyName $field -NotePropertyValue ""
        }
    }
    if (-not $ServerName) {
        $typedName = Read-Host "Server name [current: $($settings.name)] (Enter keeps)"
        if (-not [string]::IsNullOrWhiteSpace($typedName)) { $ServerName = $typedName } else { $ServerName = $settings.name }
    }
    $settings.name = $ServerName
    if (-not $ServerDescription) {
        $typedDesc = Read-Host "Server description [current: $($settings.description)] (Enter keeps)"
        if (-not [string]::IsNullOrWhiteSpace($typedDesc)) { $ServerDescription = $typedDesc } else { $ServerDescription = $settings.description }
    }
    $settings.description = $ServerDescription
    Write-Host "Server identity: '$($settings.name)' -- '$($settings.description)'"

    $json = $settings | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($localSettings, $json, (New-Object Text.UTF8Encoding($false)))

    $listJson = ConvertTo-Json -InputObject @($admins) -Compress
    [IO.File]::WriteAllText($localAdmins, $listJson, (New-Object Text.UTF8Encoding($false)))
    $localWhitelist = Join-Path $tmp "server-whitelist.json"
    [IO.File]::WriteAllText($localWhitelist, $listJson, (New-Object Text.UTF8Encoding($false)))

    # --- 8. Copy everything back (relative names, same cp rule) -------
    Push-Location $tmp
    try {
        Invoke-Kubectl -Args @("-n", $Namespace, "cp", ".\server-settings.json", "${HelperPod}:/data/config/server-settings.json")
        Invoke-Kubectl -Args @("-n", $Namespace, "cp", ".\server-adminlist.json", "${HelperPod}:/data/config/server-adminlist.json")
        if (-not $SkipWhitelist) {
            Invoke-Kubectl -Args @("-n", $Namespace, "cp", ".\server-whitelist.json", "${HelperPod}:/data/config/server-whitelist.json")
        }
    } finally { Pop-Location }

    # --- 9. Verify WITHOUT printing the password ----------------------
    # Copy the settings back out and parse them LOCALLY: the length
    # comparison happens in memory and the value is never printed.
    # (An in-pod awk check died here on the first live run --
    # PowerShell 5.1 mangles the embedded double quotes in the awk
    # program on its way to the native exe, and busybox awk answered
    # "Unexpected token". Local ConvertFrom-Json has no quoting
    # surface at all.)
    $verifyFile = Join-Path $tmp "server-settings-verify.json"
    Push-Location $tmp
    try {
        Invoke-Kubectl -Args @("-n", $Namespace, "cp", "${HelperPod}:/data/config/server-settings.json", ".\server-settings-verify.json")
    } finally { Pop-Location }
    $pvcSettings = Get-Content $verifyFile -Raw | ConvertFrom-Json
    $pwOnPvc = $pvcSettings.game_password
    if ($null -eq $pwOnPvc) { throw "Verification failed: no game_password field in the settings on the PVC. Server left at 0; helper pod left running." }
    Write-Host "Checker: game_password length on the PVC = $($pwOnPvc.Length) (expected $($plain1.Length))"
    if ($pwOnPvc.Length -ne $plain1.Length) { throw "Password length mismatch -- do NOT start the server until this is reconciled. Helper pod left running." }
    Write-Host "Checker: server name on the PVC = '$($pvcSettings.name)'"
    $adminsBack = & kubectl -n $Namespace exec $HelperPod -- cat /data/config/server-adminlist.json
    Write-Host "Checker: server-adminlist.json on the PVC = $adminsBack"
    if (-not $SkipWhitelist) {
        $whiteBack = & kubectl -n $Namespace exec $HelperPod -- cat /data/config/server-whitelist.json
        Write-Host "Checker: server-whitelist.json on the PVC = $whiteBack"
    }

    # --- 10. Helper out, server up -------------------------------------
    Invoke-Kubectl -Args @("-n", $Namespace, "delete", "pod", $HelperPod, "--wait=true")
    Write-Host "Scaling $StatefulSet back to 1..."
    Invoke-Kubectl -Args @("-n", $Namespace, "scale", "statefulset", $StatefulSet, "--replicas=1")
    $scaledDown = $false
    Invoke-Kubectl -Args @("-n", $Namespace, "rollout", "status", "statefulset/$StatefulSet", "--timeout=180s")
}
catch {
    if ($scaledDown) {
        Write-Warning "Failed AFTER scaling the server to 0. The helper pod was left running for inspection."
        Write-Warning "To abandon and restart the server as it was: kubectl -n $Namespace delete pod $HelperPod; kubectl -n $Namespace scale statefulset/$StatefulSet --replicas=1"
        Write-Warning "(The pre-change settings are also on the PVC as server-settings.json.bak.)"
    }
    throw
}
finally {
    $plain1 = $null
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "Done. Prove it with a real join:"
Write-Host "  In game: Multiplayer > Connect to address -- expect a PASSWORD PROMPT before joining,"
Write-Host "  and your name should carry admin (e.g. you can pause). Wrong/no password must fail."
