#!/usr/bin/env bash
# HOST-side helper: import the mkcert root CA into every Firefox NSS profile
# (native, Snap, Flatpak), including custom names like "Original profile".
# Run on the machine where Firefox runs — not inside the ERPNext VM.
# Fully quit Firefox before running.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run as root/sudo. Run as your normal desktop user." >&2
  exit 1
fi

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert not found on PATH. Install it first, then: mkcert -install" >&2
  exit 1
fi

if ! command -v certutil >/dev/null 2>&1; then
  echo "certutil not found. Install: sudo apt install -y libnss3-tools" >&2
  exit 1
fi

CA="$(mkcert -CAROOT)/rootCA.pem"
if [[ ! -f "$CA" ]]; then
  echo "Missing $CA — run: mkcert -install" >&2
  exit 1
fi

echo "mkcert CA: $CA"
echo
echo "Looking for Firefox NSS databases (cert9.db)..."

profiles=()
while IFS= read -r p; do
  [[ -n "$p" ]] && profiles+=("$p")
done < <(
  for root in \
    "${HOME}/.mozilla/firefox" \
    "${HOME}/snap/firefox/common/.mozilla/firefox" \
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"; do
    [[ -d "$root" ]] || continue
    find "$root" -type f -name cert9.db -printf '%h\n' 2>/dev/null || true
  done | sort -u
)

if [[ "${#profiles[@]}" -eq 0 ]]; then
  echo "No Firefox cert9.db found under the usual paths."
  echo "In Firefox open about:profiles and note the Root Directory, then:"
  echo "  certutil -d \"sql:/path/to/profile\" -A -t \"CT,C,C\" -n \"mkcert development CA\" -i \"$CA\""
  exit 1
fi

imported=0
for profile in "${profiles[@]}"; do
  echo "Importing into: $profile"
  certutil -d "sql:${profile}" -D -n "mkcert development CA" >/dev/null 2>&1 || true
  if certutil -d "sql:${profile}" -A -t "CT,C,C" -n "mkcert development CA" -i "$CA"; then
    if certutil -d "sql:${profile}" -L 2>/dev/null | grep -qi mkcert; then
      echo "  OK: mkcert CA listed in this profile"
      imported=$((imported + 1))
    else
      echo "  WARN: import returned success but mkcert not listed"
    fi
  else
    echo "  WARN: certutil import failed (is Firefox still running?)"
  fi
done

echo
echo "Imported into ${imported}/${#profiles[@]} profile(s)."
echo "Next: fully quit Firefox (every window), reopen https://erp.test"
echo
echo "If it still shows SEC_ERROR_UNKNOWN_ISSUER:"
echo "  1) about:config -> security.enterprise_roots.enabled = true -> restart Firefox"
echo "  2) about:profiles -> confirm the active profile matches one imported above"
