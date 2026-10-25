# Factorio — friends access via Tailscale (Stage 2, DECIDED 2026-10-25)

> **Public copy:** all addresses are placeholders (`<…>`) — substitute your node's real LAN/tailnet addresses. The full-detail working copy is kept private.


Plan of record for external players: **Tailscale node-share of
k3s-agent, scoped to UDP 34197 only.** Port forwarding is the parked
fallback (see `../FACTORIO.md`). Nothing here is done at first-pass
build time — the server proves itself on LAN first. This sheet is
the stage-2 session, start to finish.

Target node (verify before sharing — addresses can be re-checked in
one command):
- Machine: `k3s-agent` (the worker node), LAN `<agent-lan-ip>`
- Tailnet IP: `<agent-tailnet-ip>`, MagicDNS `<agent-magicdns>`
- Checker (any tailnet device): `tailscale status | Select-String k3s-agent`
  (PowerShell) → expect the `<agent-tailnet-ip>` line. If the IP differs,
  update this sheet *and* the grant below before proceeding.

## Step 1 — Share ONLY that machine (per friend, his console taps)

Tailscale admin console → **Machines** → `k3s-agent` → **Share…** →
send the invite to the friend's email (the account they'll sign in
with — that exact identity is what Step 2 names).

Facts that make this safe (Tailscale's sharing model):
- A shared machine is a one-way door: the friend can initiate
  connections *to* that machine only. It grants no access to any
  other tailnet device, and gives you no access to their machines.
- Revoking is one click on the same Share screen — instant off,
  no password rotation, no router change. That's the kill switch
  if a friend's account is ever compromised.

## Step 2 — Scope it to the game port (ACL grant)

Admin console → **Access controls** → add this entry to the
`grants` array (one entry; list every friend's email in `src`).
Your existing policy rules stay untouched.

```jsonc
{
    // Factorio friends — game port on the k3s-agent node ONLY.
    "src": ["friend-one@example.com", "friend-two@example.com"],
    "dst": ["<agent-tailnet-ip>"],
    "ip":  ["udp:34197"]
},
```

**The one trap to check first:** grants are additive — this entry
scopes friends to one port *only if no broader rule already lets
them in*. Before saving, search the policy for any rule whose `src`
is `"*"` or includes `autogroup:shared` with `"ip": ["*"]` (or a
`dst` of `"*"`). The default tailnet rule
(`autogroup:member` → everything) does **not** cover shared users —
they are not members — so a stock-ish policy is fine. If you find a
broad shared/wildcard rule, stop and fix that rule first; the grant
alone won't narrow it.

## Step 3 — Friend side (what to send them)

1. Install Tailscale, sign in with the invited email, accept the
   share invite.
2. Factorio → **Multiplayer → Connect to address** →
   `<agent-magicdns>:34197` (MagicDNS name works for
   shared nodes; `<agent-tailnet-ip>:34197` is the fallback form).
3. Enter the game password (the one set in `server-settings.json`
   during the build — shared out-of-band, never in this repo).
   Their Factorio username must also be on the server whitelist.

## Step 4 — Verify both directions (the proof gate)

Positive test:
- Friend joins, appears in-game; checker on any tailnet device:
  `tailscale status` → the friend's peer connection to k3s-agent
  should read `direct` (a `relay` line works but adds latency —
  note it, don't block on it; direct usually establishes itself
  after a minute as NAT punching succeeds).

Negative tests (these matter as much — the scope is the point):
- Friend tries `<agent-tailnet-ip>:22` (SSH) → must **fail**.
- Friend tries the k8s API (`<server-tailnet-ip>:6443`, the server node)
  → must **fail** (that machine was never shared at all).
- Friend pings any other tailnet device (e.g. the gaming PC) →
  must **fail**.
If any negative test succeeds, the ACL has a broader rule than
intended (see Step 2's trap) — unshare the node until it's fixed.

## Standing rules for this door

- Game password + whitelist stay ON even though the transport is
  private — Tailscale decides *who can reach the port*, Factorio
  decides *who can join the world*. Two independent gates.
- New friend = add their email to Step 1 (share) **and** Step 2
  (grant `src`) **and** the in-game whitelist. All three, or they
  get a confusing half-open door.
- Leaving friend = remove from all three; unsharing alone is the
  emergency version and is sufficient by itself.
- RCON is never part of this: it has no network exposure in any
  stage, Tailscale included.
