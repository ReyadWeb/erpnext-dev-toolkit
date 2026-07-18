# Community project board

Track starter and community-facing work for
[`ReyadWeb/erpnext-dev-toolkit`](https://github.com/ReyadWeb/erpnext-dev-toolkit).

**Live board (public):** https://github.com/users/ReyadWeb/projects/2  
**Title:** ERPNext Dev Toolkit — Community  
Linked to this repository; seeded with the starter `good first issue` tickets below.

**Product roadmap board** (milestones v1.18–v1.23): https://github.com/users/ReyadWeb/projects/3 — see [`ROADMAP-BOARD.md`](ROADMAP-BOARD.md).

Suggested columns / views: **Backlog → Ready → In progress → Done**, with filters for
`label:good first issue`, `label:help wanted`, and `label:status: accepted`.

---

## Seed issues

| # | Title |
| --- | --- |
| [#19](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/19) | docs: expand Debian 13 native troubleshooting notes |
| [#20](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/20) | docs: add a VPS provider validation record |
| [#21](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/21) | ux: clarify Docker readiness-timeout warning next steps |
| [#22](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/22) | docs: improve object-backup help descriptions |
| [#23](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/23) | docs: link SUPPORT/CONTRIBUTING from next-steps surfaces |

Add new `good first issue` / `help wanted` tickets to **Ready** as they are opened.

## Maintainer notes (recreate / re-link)

GitHub Projects requires the `project` / `read:project` token scopes:

```bash
gh auth refresh -s project,read:project
gh project create --owner ReyadWeb --title "ERPNext Dev Toolkit — Community"
# link repo + add items — see gh project item-add
```

## Contributor entry points

- [Issue forms](https://github.com/ReyadWeb/erpnext-dev-toolkit/issues/new/choose)
- [`CONTRIBUTING.md`](../CONTRIBUTING.md)
- [`docs/DEVELOPMENT.md`](DEVELOPMENT.md)
