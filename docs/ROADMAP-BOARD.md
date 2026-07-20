# Public roadmap board

We track active product work in the open so operators and contributors can see
what is planned, in progress, and next.

**Live board:** https://github.com/users/ReyadWeb/projects/3  
**Title:** ERPNext Dev Toolkit — Roadmap  
**Plan of record:** [`ROADMAP.md`](../ROADMAP.md)  
**Community starter board** (good first issues): [`COMMUNITY-BOARD.md`](COMMUNITY-BOARD.md) → https://github.com/users/ReyadWeb/projects/2

---

## How to read the board

| Status | Meaning |
|--------|---------|
| **Todo** | Accepted roadmap work, not started |
| **In Progress** | Actively being implemented |
| **Done** | Shipped / closed |

Issues use label `roadmap` plus `milestone:v1.18` / `milestone:v1.19` / `milestone:v1.20+`.
GitHub **Milestones** `v1.18.0` … `v1.23.0` group epics and child tasks.

---

## Seeded epics (v1.18–v1.23)

| Milestone | Epic |
|-----------|------|
| v1.18.0 | [#57](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/57) Security Hardening Closure |
| v1.18.1 | [#58](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/58) Local VM Stable IP Foundation |
| v1.18.2 | [#82](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/82) Repository Security & Governance Hardening |
| v1.18.3 | [#59](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/59) Frontend Asset Readiness Gaps |
| v1.19.0 | [#60](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/60) Guarded Auto-Healing MVP |
| v1.19.1 | [#61](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/61) Auto-Healing Hardening |
| v1.19.8 | [#107](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/107) Browser Asset Consistency Closure |
| v1.19.9 | Bare HTTP port-80 browser path (follow-on from [#107](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/107) field) |
| v1.19.10 | Frappe-aligned frontend assets ([FRAPPE-FRONTEND-ASSETS.md](FRAPPE-FRONTEND-ASSETS.md)) |
| v1.19.11 | Stale `assets_json` Redis :13000 fix + stable release CI gate |
| v1.19.12 | Post-HTTPS settle before browser URLs (no reboot workaround) |
| v1.19.13 | [#108](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/108) CLI Page UX Architecture |
| v1.20.0 | [#62](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/62) External Watchdog Foundation |
| v1.21.0 | [#63](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/63) CloudPanel / Agent API Foundation |
| v1.22.0 | [#64](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/64) Real VPS Validation Matrix |
| v1.23.0 | [#65](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/65) Documentation and Launch Polish |

### v1.18.0 child work (**shipped** in v1.18.0)

| Issue | Focus |
|-------|--------|
| [#66](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/66) | Strict allowlist parser for `health.env` (**Done**) |
| [#67](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/67) | Strict off-VM SSH host-key mode (**Done**) |
| [#68](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/68) | Remove or justify remaining `eval` patterns (**Done**) |
| [#69](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/69) | CI: secret scanning, Scorecard, shfmt, risky-shell tests (**Done**) |

**v1.18.1 shipped:** [#58](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/58) Local VM Stable IP Foundation (**Done**).

**v1.18.2 shipped:** [#82](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/82) Repository Security & Governance Hardening (**Done**).

**v1.18.3 shipped:** [#59](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/59) Frontend Asset Readiness Gaps (**Done**).

**v1.19.0 shipped:** [#60](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/60) Guarded Auto-Healing MVP (**Done**).

**v1.19.1 shipped:** [#61](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/61) Auto-Healing Hardening (**Done**).

**Current focus:** v1.19.12 post-HTTPS settle (field validation before/after HTTPS).  
**Next:** [#108](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/108) — v1.19.13 CLI Page UX.  
**Deferred:** [#62](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/62) — v1.20.0 until 1.19.12 + 1.19.13 are field-validated.

---

## Maintainer notes

```bash
gh auth refresh -s project,read:project
gh project view 3 --owner ReyadWeb
gh issue list --label roadmap --milestone v1.18.0
```

When opening new roadmap work: create the issue with label `roadmap`, assign the
matching GitHub Milestone, add it to project 3, and link it from the relevant
ROADMAP section when useful.
