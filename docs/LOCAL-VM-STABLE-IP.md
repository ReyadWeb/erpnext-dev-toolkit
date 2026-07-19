# Local VM Stable IP

Keep `erp.test` (or your local site name) and local HTTPS working when the guest
VM IP changes after reboot.

## Why it breaks

Local installs map a friendly hostname on the **host** machine:

```text
192.168.122.42  erp.test
```

If the guest gets a new DHCP address after reboot, browsers still hit the old IP
(or fail DNS), while the toolkit inside the guest reports a different address.
mkcert/self-signed HTTPS stays bound to the hostname, so fixing hosts (or
pinning the guest IP) restores access.

## Quick toolkit commands

| Command | Purpose |
|---------|---------|
| `sudo erpnext-dev local-ip-status` | Current IP, DHCP vs static signals, saved mapping |
| `sudo erpnext-dev local-ip-plan` | Ranked options for this host/hypervisor |
| `sudo erpnext-dev local-ip-drift-check` | Saved IP vs current IP |
| `sudo erpnext-dev local-ip-save` | Record the current mapping |
| `sudo erpnext-dev local-static-ip-wizard` | Guest static IP + backup (Netplan or ifupdown) |
| `sudo erpnext-dev local-static-ip-rollback` | Restore prior guest network config |
| `sudo erpnext-dev hosts-command` | Print host `/etc/hosts` repair commands |
| `sudo erpnext-dev local-ip-menu` | Boxed submenu |

Menu path: **Main menu → Local network**.

## Recommended order

`local-dev-quickstart` offers this checkpoint **before install** and again in
post-install guided follow-ups if the guest is still on DHCP.

1. **Prefer a hypervisor DHCP reservation** (stable lease by MAC) when your host
   supports it — see platform notes below.
2. **Or pin a static address inside the guest** with
   `local-static-ip-wizard` (Netplan on Ubuntu; classic ifupdown on Debian
   guests that do not ship Netplan — backup + apply + rollback either way).
3. **Update HOST `/etc/hosts`** whenever the guest IP changes
   (`hosts-command`).
4. **Save the mapping** with `local-ip-save` so `local-ip-drift-check` can warn
   you after the next reboot.
5. After HTTPS, accept the guided **service restart confirmation** (or run
   `sudo erpnext-dev restart`) so ERPNext/nginx settle without a full VM reboot.

## Platform notes

### KVM / libvirt (typical Linux host)

Reserve a DHCP host entry for the VM MAC on the `default` network, or use the
toolkit helpers:

```bash
sudo erpnext-dev kvm-identify
sudo erpnext-dev kvm-fixed-ip-guide
```

Example (adjust MAC/name/IP):

```bash
sudo virsh net-update default add ip-dhcp-host \
  "<host mac='AA:BB:CC:DD:EE:FF' name='erpnext-dev' ip='192.168.122.50'/>" \
  --live --config
```

### VirtualBox

Use a Host-Only adapter with a fixed guest IP, or reserve via `VBoxManage
dhcpserver modify … --fixed-address / --mac-address`. Guest Netplan static IP
also works.

### Hyper-V

The Default Switch NAT is dynamic. Prefer an External/Internal switch with a
static guest IP, or reserve by MAC on your LAN router. Guest Netplan static IP
is the most portable fix inside Ubuntu/Debian guests.

### VMware / Proxmox

- **VMware Fusion/Workstation:** DHCP host stanza in the vmnet DHCP config, or
  guest static IP.
- **Proxmox:** set a static IP in the guest, or use dnsmasq/DHCP reservations on
  the bridge — same Netplan wizard applies inside Ubuntu/Debian guests.

### Universal fallback (any hypervisor)

```bash
sudo erpnext-dev local-static-ip-wizard
```

This writes `/etc/netplan/99-erpnext-dev-static.yaml`, keeps a backup under
`/etc/erpnext-dev/local-ip-backups/`, and records `/etc/erpnext-dev/local-ip.state`.

Rollback:

```bash
sudo erpnext-dev local-static-ip-rollback
```

## Hosts repair

The toolkit cannot edit the host OS from inside the guest. Always run the printed
commands on the physical host:

```bash
sudo erpnext-dev hosts-command
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Browser cannot open `https://erp.test` after reboot | `local-ip-drift-check`, then refresh hosts |
| Drift says saved ≠ current | Update hosts, then `local-ip-save` |
| Netplan apply lost SSH | Wait for `netplan try` timeout, or restore console + `local-static-ip-rollback` |
| WSL2 | Map the site name to `127.0.0.1` on Windows; do not chase the WSL IP |

## Related

- [`local-fixed-ip-guide`](../README.md) — older hypervisor-oriented guide (still available)
- Local HTTPS: `local-ssl-menu` / mkcert setup
- Local quickstart warns about dynamic IP risk before guided setup
