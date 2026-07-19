# Health, monitoring, and guarded auto-healing

Architecture of record for ERPNext-aware operations observability in the
**ERPNext Developer Toolkit**. Implementation ships in phases (v1.16+); this
document defines the model before automation is allowed to act.

Related: [`ROADMAP.md`](../ROADMAP.md) · [`lib/dashboard.sh`](../lib/dashboard.sh) ·
[`lib/healing.sh`](../lib/healing.sh) · [`lib/health.sh`](../lib/health.sh)

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

Software inside a dead VM cannot reboot itself. v1.16–v1.19 cover Case A
(observe → guarded heal). v1.20 defines the external heartbeat / watchdog
**contract** for Case B.

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

1. **Host** — load/core, sampled CPU busy %, MemAvailable, swap, disk %,
   inodes, sampled I/O wait %, uptime, reboot-required. (RO filesystem / OOM
   remain optional future signals.)
2. **Frappe / ERPNext** — HTTP status + latency, DB/Redis reachability,
   best-effort workers + scheduler freshness, Socket.IO / ports, Redis queue
   depth when `redis-cli` reaches host Redis.
3. **Engine runtime** — native (nginx, supervisor/systemd, ports) or Docker
   (running/total, unhealthy, restarting, max RestartCount loop detection).
4. **Protection / DR** — HTTPS + certificate days remaining (thresholded),
   firewall, Fail2Ban, backup ages/verify, restore rehearsal, toolkit
   integrity, healing mode / would-heal (execute when mode is `safe`/`advanced`).

---

## Recovery ladder (design; executed from v1.19)

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

Default remains `monitor`. Operators enable execution with
`erpnext-dev healing-enable-safe` (writes `HEALING_MODE=safe` into
`/etc/erpnext-dev/healing.env`). `advanced` shares the safe restart ladder in
v1.19.x (no host reboot yet).

### Five safety controls (non-negotiable for v1.19+)

1. **Sustained duration** — threshold exceeded continuously for N minutes.
2. **Consecutive failures** — e.g. 3 failed HTTP checks before action.
3. **Cooldown** — do not repeat the same action within the cooldown window.
4. **Max actions per window** — then `AUTO-HEALING LOCKED` (manual review).
5. **Recovery verification** — every action records before/after and success/failure.

Root-run policy files must use a **strict allowlist parser** — never `source` as
shell. Thresholds stay in `health.env`; healing policy lives in
`/etc/erpnext-dev/healing.env` (`HEALING_MODE`, `HEALING_MAX_*`, per-action
switches, `HEALING_SIMULATE`, `HEALING_ALERT_ON_LOCKOUT`). Legacy
`HEALTH_HEALING_*` keys in `health.env` still apply, then `healing.env` overrides.

---

## Storage

| Path | Purpose |
|------|---------|
| `/etc/erpnext-dev/health.env` | Optional policy overrides (thresholds, `HEALTH_ALERT_WEBHOOK_URL`, `HEALTH_ALERT_ON`). **Strict allowlist parser** (never `source`d); root-owned `600`/`640`; HTTPS webhooks (localhost HTTP allowed). |
| `/etc/erpnext-dev/health-check.state` | Compat summary for existing readers (dual-written from snapshot) |
| `/var/lib/erpnext-dev/metrics/` | `current.json`, rolling `history.jsonl` |
| `/var/lib/erpnext-dev/incidents/` | Incident JSON records + `latest.json` |
| `/etc/erpnext-dev/healing.env` | Dedicated healing policy (allowlist parser; never sourced) |
| `/var/lib/erpnext-dev/healing/` | `state.json` (cooldown / last action / lockout) + `audit.jsonl` |

Core toolkit has **no Prometheus dependency**. `erpnext-dev health-metrics`
emits OpenMetrics text for optional scrapers.

### v1.17 monitoring behaviour

On every `dashboard` / `health-check` / `health-snapshot` run:

1. Append a compact sample to `metrics/history.jsonl` (pruned to
   `HEALTH_HISTORY_MAX_LINES`, default 2016).
2. Update `healing/state.json` consecutive-failure streaks and a **would-heal**
   suggestion when the threshold is met.
3. If mode is `safe`/`advanced` and not locked, execute the candidate restart,
   verify recovery, record a `healing_action` incident, and lock on repeated
   failure or max-actions window.
4. If overall status **transitions** into DEGRADED/CRITICAL (or recovers to
   HEALTHY), write an incident under `incidents/` and optionally alert.
5. Alerts: `logger` + stderr; optional POST to `HEALTH_ALERT_WEBHOOK_URL`
   when `HEALTH_ALERT_ON` matches (`CRITICAL` default).

CLI: `incidents`, `incident-show`, `health-history`, `health-metrics`,
`healing-status`, `healing-policy`, `healing-history`, `healing-enable-safe`,
`healing-disable`, `healing-unlock`.

---

## Milestone map

| Version | Focus |
|---------|--------|
| **v1.16.0** | Canonical snapshot + Operations Dashboard (`dashboard`, `--watch`, `--json`) |
| **v1.17.0** | Persistent history, incidents, threshold engine, alert hooks, OpenMetrics |
| **v1.18.0** | Security hardening for root policy files (safe `health.env` parser) before healing |
| **v1.18.1–.3** | Local IP stability + repo governance + frontend asset readiness (see ROADMAP) |
| **v1.19.0** | Guarded auto-healing MVP (modes + ladder + locks) |
| **v1.19.1** | Auto-healing hardening (dedicated policy, audit, richer dashboard) |
| **v1.20.0** | External watchdog / heartbeat contract for CloudPanel |

Do not ship monitoring and automatic reboot in one release. Close root config
safety and readiness gaps first; then let the health model drive automation.
