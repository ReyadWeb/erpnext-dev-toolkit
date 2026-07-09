# Update GitHub repo — v1.1.58

```bash
cd ~/Projects/erpnext-dev-installer

rm -rf /tmp/erpnext-dev-installer-v1158
mkdir -p /tmp/erpnext-dev-installer-v1158

unzip ~/Downloads/erpnext-dev-installer-v1.1.58.zip -d /tmp/erpnext-dev-installer-v1158

cp /tmp/erpnext-dev-installer-v1158/erpnext-dev.sh .
cp /tmp/erpnext-dev-installer-v1158/README.md .
cp /tmp/erpnext-dev-installer-v1158/ROADMAP.md .
cp /tmp/erpnext-dev-installer-v1158/CHANGELOG.md .
cp /tmp/erpnext-dev-installer-v1158/TESTING.md .
cp /tmp/erpnext-dev-installer-v1158/PRODUCTION-VALIDATION.md .
cp /tmp/erpnext-dev-installer-v1158/LICENSE .
cp /tmp/erpnext-dev-installer-v1158/GITHUB-UPDATE-v1.1.58.md .

chmod +x erpnext-dev.sh
```

## Validate before commit

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "backup-server-setup"
./erpnext-dev.sh --help | grep -n "generate-off-vm-backup-key"
./erpnext-dev.sh --help | grep -n "off-vm-backup-guided-setup"
printf 'q\n' | ./erpnext-dev.sh off-vm-backup-wizard

grep -n "v1.1.58" CHANGELOG.md
grep -n "v1.1.58" TESTING.md
grep -n "v1.1.58" ROADMAP.md
grep -n "v1.1.58" PRODUCTION-VALIDATION.md
grep -n "Guided off-VM backup" erpnext-dev.sh
grep -n "Prepare this server as backup target" erpnext-dev.sh
grep -n "backup-server-setup" README.md PRODUCTION-VALIDATION.md
```

## Commit and tag

```bash
git status

git add erpnext-dev.sh README.md ROADMAP.md CHANGELOG.md TESTING.md PRODUCTION-VALIDATION.md LICENSE GITHUB-UPDATE-v1.1.58.md
git add -u

git commit -m "Release v1.1.58 add guided off-VM backup setup"

git push origin main

git tag v1.1.58
git push origin v1.1.58
```

## Final confirmation

```bash
git status
git tag --list "v1.1.58"
git log --oneline -1
```

Expected result:

```text
working tree clean
v1.1.58
Release v1.1.58 add guided off-VM backup setup
```
