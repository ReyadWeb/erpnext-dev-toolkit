# Health, monitoring, and guarded auto-healing

Architecture of record for ERPNext-aware operations observability in the
**ERPNext Developer Toolkit**. Implementation ships in phases (v1.16+); this
document defines the model before automation is allowed to act.

Related: [`ROADMAP.md`](../ROADMAP.md) · [`lib/dashboard.sh`](../lib/dashboard.sh) ·
[`lib/health.sh`](../lib/health.sh)

---

## Goals

- One **canonical health snapshot** for native and Docker, human CLI and JSON,
  current dashboard and a future CloudPanel.
- Layered **Observe → Detect → Heal → Record → Alert** — never “CPU high → reboot”.
- Resource thresholds alone **alert**; healing requires **service failure +
  sustained evidence**.

---

## Case A vs Case B

| Case | Situation | Who can recover |
|------|-----------|-----------------|
| **A** | VM is alive; ERPNext/resources unhealthy | In-guest toolkit health agent |
| **B** | VM frozen, kernel hung, or powered off | **External** monitor / CloudPanel / provider API (and optionally hardware watchdog) |

Software inside a dead VM cannot reboot itself. v1.16–v1.18 cover Case A only.
v1.19 defines the external heartbeat / watchdog **contract** for Case B.

---

## Health states (canonical)

Exactly four states everywhere (CLI, JSON, alerts, future healing):

| State | Meaning |
|-------|---------|
| `HEALTHY` | Required functions operating normally |
| `DEGRADED` | Available, but action is advisable |
| `CRITICAL` | Major function unavailable or data/recovery risk |
| `UNKNOWN` | Check could not determine state reliably |

**Overall status** = worst-of required checks. `UNKNOWN` must not be treated as
`CRITICAL` when the probe itself failed (for example, no sudo, missing tool).

Legacy health-check rows that used `OK` / `WARN` map to `HEALTHY` / `DEGRADED`
(and `FAIL` → `CRITICAL`) for compatibility in `/etc/erpnext-dev/health-check.state`.

---

## Observe layers

1. **Host** — load/core, CPU, MemAvailable, swap, disk %, inodes, I/O wait, RO
   filesystem, uptime, OOM signals, basic connectivity, reboot-required.
2. **Frappe / ERPNext** — HTTP status + latency, DB/Redis reachability, workers,
   scheduler, Socket.IO / ports, queue pressure where cheap.
3. **Engine runtime** — native (nginx, supervisor/systemd, ports) or Docker
   (compose project, container health, restart counts). Build on Docker restart
   policies; detect restart loops.
4. **Protection / DR** — HTTPS, firewall, Fail2Ban, backup ages/verify, restore
   rehearsal, toolkit integrity, healing mode / arm state.

---

## Recovery ladder (design; executed from v1.18)

```text
Level 0  Observe only
Level 1  Retry health check
Level 2  Restart affected component
Level 3  Restart ERPNext application stack
Level 4  Safe emergency cleanup (explicit allow-list only)
Level 5  Guarded VM reboot (Advanced mode opt-in only)
Level 6  External watchdog / provider recovery (outside guest)
```

### Healing modes

| Mode | Behavior |
|------|----------|
| `monitor` | Observe / detect / record / alert only |
| `safe` | Component + stack restarts; **never** host reboot (recommended default when healing ships) |
| `advanced` | Explicit opt-in; adds guarded reboot under policy |

v1.16 always reports mode `monitor` and state `not_armed` (no automation).

### Five safety controls (non-negotiable for v1.18+)

1. **Sustained duration** — threshold exceeded continuously for N minutes.
2. **Consecutive failures** — e.g. 3 failed HTTP checks before action.
3. **Cooldown** — do not repeat the same action within the cooldown window.
4. **Max actions per window** — then `AUTO-HEALING LOCKED` (manual review).
5. **Recovery verification** — every action records before/after and success/failure.

---

## Storage

| Path | Purpose |
|------|---------|
| `/etc/erpnext-dev/health.env` | Thresholds / mode / feature flags (v1.17+) |
| `/etc/erpnext-dev/health-check.state` | Compat summary for existing readers (dual-written from snapshot) |
| `/var/lib/erpnext-dev/metrics/` | `current.json`, rolling `history.jsonl` (v1.17+) |
| `/var/lib/erpnext-dev/incidents/` | Incident records (v1.17+) |
| `/var/lib/erpnext-dev/healing/` | Healing state / locks (v1.18+) |

Core toolkit has **no Prometheus dependency**. Optional OpenMetrics export is a
later integration for advanced users.

---

## Milestone map

| Version | Focus |
|---------|--------|
| **v1.16.0** | Canonical snapshot + Operations Dashboard (`dashboard`, `--watch`, `--json`) |
| **v1.17.0** | Persistent history, incidents, threshold engine, alert hooks |
| **v1.18.0** | Guarded auto-healing (modes + ladder + locks) |
| **v1.19.0** | External watchdog / heartbeat contract for CloudPanel |

Do not ship monitoring and automatic reboot in one release. Make the health
model trustworthy first; then let that model drive automation.
