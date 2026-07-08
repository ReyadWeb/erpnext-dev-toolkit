# Update GitHub repo — v1.1.53

## Update GitHub repo

```bash
cd ~/Projects/erpnext-dev-installer

rm -rf /tmp/erpnext-dev-installer-v1153
mkdir -p /tmp/erpnext-dev-installer-v1153

unzip ~/Downloads/erpnext-dev-installer-v1.1.53.zip -d /tmp/erpnext-dev-installer-v1153

cp /tmp/erpnext-dev-installer-v1153/erpnext-dev.sh .
cp /tmp/erpnext-dev-installer-v1153/README.md .
cp /tmp/erpnext-dev-installer-v1153/ROADMAP.md .
cp /tmp/erpnext-dev-installer-v1153/CHANGELOG.md .
cp /tmp/erpnext-dev-installer-v1153/TESTING.md .
cp /tmp/erpnext-dev-installer-v1153/PRODUCTION-VALIDATION.md .
cp /tmp/erpnext-dev-installer-v1153/LICENSE .
cp /tmp/erpnext-dev-installer-v1153/GITHUB-UPDATE-v1.1.53.md .

chmod +x erpnext-dev.sh
```

## Validate before commit

```bash
bash -n erpnext-dev.sh
./erpnext-dev.sh version
./erpnext-dev.sh --help | grep -n "public-vm-guided-setup"
grep -n "SSH host key changed" README.md
grep -n "REMOTE HOST IDENTIFICATION HAS CHANGED" README.md
grep -n "known_hosts" PRODUCTION-VALIDATION.md
grep -n "ssh-keygen" TESTING.md
grep -n "v1.1.53" CHANGELOG.md
```

## Commit and tag

```bash
git status

git add erpnext-dev.sh README.md ROADMAP.md CHANGELOG.md TESTING.md PRODUCTION-VALIDATION.md LICENSE GITHUB-UPDATE-v1.1.53.md
git add -u

git commit -m "Release v1.1.53 document VPS rebuild SSH recovery"

git push origin main

git tag v1.1.53
git push origin v1.1.53
```

## Final confirmation

```bash
git status
git tag --list "v1.1.53"
git log --oneline -1
```

Expected result:

```text
working tree clean
v1.1.53
Release v1.1.53 document VPS rebuild SSH recovery
```
