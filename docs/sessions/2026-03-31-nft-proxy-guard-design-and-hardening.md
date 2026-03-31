# nft-proxy-guard: Design and Hardening

Designed, iterated, and hardened an nftables-based automatic connection-limiting ruleset for a LAN transparent/explicit proxy gateway.

## Summary

The session started from `nft-http-proxy-block.sh`, a manually-managed nftables script that dropped connections from specific IPs. Through a series of design improvements it was completely rewritten and renamed to `nft-proxy-guard.sh` — a fully automatic, production-ready mitigation system for infected LAN clients opening excessive TCP connections.

Key design questions answered along the way: correct nftables flag semantics (`flags dynamic`, `flags timeout`, `ct count` + timeout incompatibility), hook placement for transparent proxy traffic (prerouting vs input), proper use of `add` vs `update` in dynamic sets, and several hardening additions (interface restriction, counter visibility, `ct state invalid`, log prefix on ban events).

## Changed files

- `dotsh/bin/nft-http-proxy-block.sh` — original file; replaced by the new script
- `dotsh/bin/nft-restricted-ips.sh` — intermediate name; accumulated features then superseded
- `dotsh/bin/nft-proxy-guard.sh` — final script; fully automatic prerouting-based mitigation

### Evolution of `nft-proxy-guard.sh` (née `nft-http-proxy-block.sh`)

| Stage | Key change |
|---|---|
| Initial | Manual `add/del` commands; `update @set` refreshing timeout; `flags dynamic` on connlimit set with timeout |
| Stage 2 | Replace per-port drop with `ct count over N`; drop `flags dynamic` since no packet-path `add`/`update` |
| Stage 3 | Rename to `nft-restricted-ips.sh`; remove `PROXY_PORT` filter; scope to `saddr` only |
| Stage 4 | Add `ether_addr` MAC set (ARP/NDP lookup via `ip neigh show`) |
| Stage 5 | Add `flags dynamic` auto-ban sets; meter-based rate detection; `add` (not `update`) semantics |
| Stage 6 | Full redesign to `nft-proxy-guard.sh`: automatic-only, `start/stop/reload/unban` commands; correct `ct count` (no timeout on connlimit set) |
| Stage 7 | Multi-subnet support: `LAN4_SUBNETS`/`LAN6_SUBNETS` bash arrays → nft `flags interval` sets |
| Stage 8 | Hook moved from `input` to `prerouting priority filter` to cover transparent proxy (TPROXY) traffic |
| Stage 9 | Hardening: `LAN_IFACE` (iifname restriction), `ct state invalid counter drop`, `counter` on all drop rules, `log prefix "proxy-guard ban:"` on ban, `size 4096` on autoban sets |

## Git commits

- `04d9507` feat: add LAN_IFACE, ct invalid drop, counter, log prefix, and set size to nft-proxy-guard.sh
- `b7e587e` feat: impl dotsh/bin/nft-proxy-guard.sh
- `59d9685` feat: impl restricted_mac on dotsh/bin/nft-restricted-ips.sh
- `d816dd1` feat: add nft-restricted-ips.sh script for managing restricted IPs

## Notes

### nftables semantics: critical correctness rules

- **`ct count` + `timeout` are incompatible.** Sets used with `ct count` must NOT have `timeout` — conntrack timers handle element expiry. Adding `timeout` produces "Operation is not supported" at runtime. Only `flags dynamic` is needed.
- **`add` vs `update` in dynamic sets:**
  - `update @set { ip saddr timeout T }` — rewrites timeout on every packet match. Causes ban timer to be refreshed indefinitely if the client keeps sending traffic.
  - `add @set { ip saddr timeout T }` — writes the element once; if already present, does nothing. Timeout is fixed at first insertion. Always use `add` for auto-ban.
- **`flags timeout` purpose:** enables per-element timeout tracking. Required for auto-ban sets. Has nothing to do with refreshing timeouts — that is caused by `update`.
- **`flags dynamic` purpose:** allows packet-path rules to add/update set elements. Required for meter sets and auto-ban sets. NOT required for static sets (e.g., `lan4_subnets`).

### Hook placement for transparent proxy

- Transparent proxy clients connect to arbitrary remote IPs — their traffic has `dport != 7890`. In the `input` chain, TPROXY-redirected traffic is already delivered to the proxy socket; `dport 7890` matching only catches explicit proxy connections.
- Using `type filter hook prerouting priority filter` (priority 0) ensures rules run AFTER TPROXY mangle (priority -150) but BEFORE delivery/forwarding. This catches ALL TCP from LAN regardless of destination or proxy mode.
- **Caveat:** conntrack runs at priority −200, so conntrack entries are already written before this chain. `ct count` is accurate (counts existing entries) but does not prevent the SYN itself from entering conntrack. Complement with `nf_conntrack_max` tuning and `tcp_syncookies=1`.

### Operational visibility

```bash
# See packet counters per rule
nft list chain inet proxy_guard prerouting

# See banned IPs and remaining timeout
nft list set inet proxy_guard auto_banned_ip4

# See meter state (token bucket fill per IP)
nft list meter inet proxy_guard rate_detect_ip4

# See clients tracked by connlimit
nft list set inet proxy_guard connlimit_ip4

# Watch live ban events
journalctl -kf | grep "proxy-guard ban:"
```

### MAC address restriction: not used in final design

MAC sets (via `ether_addr` + ARP/NDP lookup) were explored but removed in the final design. They only work for directly connected L2 clients (invalid through a router), require manual or deferred lookup (`ip neigh show`), and MAC spoofing is low-effort. The automatic per-saddr approach is more robust.

### Meter vs set for rate detection

nftables meters are anonymous inline maps embedded in rules. They are the correct primitive for per-key token bucket rate limiting. Named meters (`meter foo { ... }`) persist across rule evaluations and can be inspected with `nft list meter`. The key `ip saddr` (not `ip saddr . ip daddr . tcp dport`) is used intentionally: detection is per-client globally, not per-destination-flow.

### `iifname` restriction

Setting `LAN_IFACE` (e.g., `br0`) prepends `iifname "br0"` to LAN-specific rules. This prevents WAN-side packets with spoofed LAN source IPs from interacting with the meter and ban set. `ct state invalid drop` is intentionally NOT restricted to one interface — it applies globally.
