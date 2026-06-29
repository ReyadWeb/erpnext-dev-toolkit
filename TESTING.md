# Testing v0.8.16

## 1. Syntax check

```bash
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.8.16"
```

## 2. Fresh VM storage test

Run inside a fresh Ubuntu VM:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh storage-debug
./install-erpnext-dev.sh setup
```

Expected behavior when the VM disk is larger than the root filesystem:

```text
Storage: root uses 39G of 260G disk.
Expand root storage now? [Y/n]:
```

After choosing `Y`, setup should continue and the resource check should show enough free disk:

```text
OK: Available disk: 200+ GB
```

## 3. Runtime validation

After setup:

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh service-summary
```

Expected:

```text
Runtime                      OK      Running via service
Service                      OK      Running
Autostart                    OK      Enabled
Bench web                    OK      port 8000 listening
Socket.io                    OK      port 9000 listening
Bench Redis queue            OK      port 11000 listening
Bench Redis cache            OK      port 13000 listening
```

## 4. Reboot test

```bash
sudo reboot
```

After reconnecting:

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh doctor
```

Expected: service is running and all required development ports are listening.

## 5. Security regression test

The install summary must not print the generated Administrator password.

Expected summary wording:

```text
Password: saved in the credentials file
View with: sudo cat /home/frappe/erpnext-dev-credentials.txt
```

Check log permissions:

```bash
ls -l /tmp/erpnext-dev-installer-*.log | tail -1
```

Expected permissions should not be world-readable:

```text
-rw-------
```

## 6. Lock test

Start a mutating command in one terminal, then quickly run another mutating command in a second terminal.

Expected:

```text
ERROR: Another installer task is already running.
```
