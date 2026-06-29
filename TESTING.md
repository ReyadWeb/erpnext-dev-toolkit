# TESTING - v0.8.8

## Goal

Validate that production-domain planning commands work without changing the local developer environment.

## Verify version

```bash
grep -n "SCRIPT_VERSION" install-erpnext-dev.sh
```

Expected:

```text
SCRIPT_VERSION="0.8.8"
```

## Planning commands

```bash
./install-erpnext-dev.sh domain-config
./install-erpnext-dev.sh production-readiness
./install-erpnext-dev.sh production-domain-guide
./install-erpnext-dev.sh production-ssl-guide
```

Expected:

- Commands should print planning guidance only.
- No production changes should be applied.
- Local ERPNext service should remain unchanged.

## Test with future domain variable

```bash
PRODUCTION_DOMAIN=erp.company.com ./install-erpnext-dev.sh domain-config
PRODUCTION_DOMAIN=erp.company.com ./install-erpnext-dev.sh production-readiness
```

Expected:

```text
Production domain OK erp.company.com
```

## Existing local checks should still pass

```bash
./install-erpnext-dev.sh site-config
./install-erpnext-dev.sh doctor
./install-erpnext-dev.sh runtime-status
```

Expected:

```text
Bench web         OK
Socket.io         OK
Site app: frappe  OK
Site app: erpnext OK
```
