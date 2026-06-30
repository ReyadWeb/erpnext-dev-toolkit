# TESTING v0.8.20

## Syntax

```bash
bash -n install-erpnext-dev.sh
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.8.20"
```

## Storage regression test

On a VM whose root filesystem is already expanded:

```bash
./install-erpnext-dev.sh storage-status
```

Expected:

```text
Expansion OK not needed
```

It should not continue to recommend expansion when:

- VG free is 0, and
- growable disk tail is 0.

## Fresh cloned VM storage test

On a cloned VM where the virtual disk is larger than the root partition:

```bash
./install-erpnext-dev.sh storage-status
./install-erpnext-dev.sh expand-root-storage
./install-erpnext-dev.sh storage-status
df -h /
```

Expected before expansion:

```text
Expansion WARN recommended
```

Expected after expansion:

```text
Expansion OK not needed
```

## Runtime validation

```bash
./install-erpnext-dev.sh runtime-status
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh verify-access
./install-erpnext-dev.sh ssl-status
```
