# ERPNext Developer Installer v0.8.16

Local ERPNext/Frappe developer VM installer for Ubuntu 24.04/26.04.

## Quick start

Run inside the ERPNext VM:

```bash
curl -fsSL https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/main/install-erpnext-dev.sh -o install-erpnext-dev.sh
chmod +x install-erpnext-dev.sh
./install-erpnext-dev.sh setup
```

During setup, choose a local site name:

```text
Local site name [erp.test]:
```

Press Enter for `erp.test`, or enter a custom local name such as `erp08.test`.

## v0.8.16 highlights

- Keeps the v0.8.15 storage expansion fix as the stable baseline.
- Adds safer private installer logs with `600` permissions.
- Stops printing generated passwords in the terminal summary/log.
- Adds an installer lock to reduce conflicting simultaneous setup/repair/service runs.
- Adds a compact post-install validation summary.
- Updates stale test/release documentation.
- Release ZIP should be clean and should not include `.git`.

## Storage expansion flow

The installer checks storage before the main disk-space resource check.

If a cloned/resized VM has a larger virtual disk than Ubuntu is using, setup can prompt:

```text
Storage: root uses 39G of 260G disk.
Expand root storage now? [Y/n]:
```

For common Ubuntu LVM roots, the generic flow is:

```bash
sgdisk -e <disk> || true
partprobe <disk> || true
growpart <disk> <partition-number>
pvresize <physical-volume-partition>
lvextend -r -l +100%FREE <root-logical-volume>
```

The script derives the disk, partition number, physical volume, and logical volume from the VM. It does not hardcode `/dev/vda3` or `ubuntu-vg`.

Useful storage commands:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh storage-debug
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh verify-storage
```

## Local domain flow

After setup, run the shown `/etc/hosts` command on the HOST machine, not inside the VM.

Example:

```bash
sudo sed -i '/[[:space:]]erp08\.test$/d' /etc/hosts
echo "192.168.122.181 erp08.test" | sudo tee -a /etc/hosts
```

Then test from the host:

```bash
curl -I http://erp08.test:8000
```

## Local SSL flow

Inside the VM:

```bash
./install-erpnext-dev.sh create-self-signed-local-cert
./install-erpnext-dev.sh configure-local-ssl
./install-erpnext-dev.sh verify-local-ssl
```

Host tests:

```bash
curl -I http://erp08.test
curl -kI https://erp08.test
curl -I http://erp08.test:8000
```

For browser-trusted local SSL, use:

```bash
./install-erpnext-dev.sh mkcert-guide
./install-erpnext-dev.sh browser-trust-guide
```

## Credentials and logs

The installer saves credentials in:

```text
/home/frappe/erpnext-dev-credentials.txt
```

View them inside the VM with:

```bash
sudo cat /home/frappe/erpnext-dev-credentials.txt
```

Installer logs are written to `/tmp/erpnext-dev-installer-*.log` with private permissions.

## Optional apps

Install optional apps only after the base install and access are verified:

```bash
./install-erpnext-dev.sh app-library
```

Available app commands include:

```bash
./install-erpnext-dev.sh install-crm
./install-erpnext-dev.sh install-hrms
./install-erpnext-dev.sh install-helpdesk
./install-erpnext-dev.sh install-insights
```

## Health checks

```bash
./install-erpnext-dev.sh site-config
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh service-summary
./install-erpnext-dev.sh ssl-status
./install-erpnext-dev.sh doctor
```
