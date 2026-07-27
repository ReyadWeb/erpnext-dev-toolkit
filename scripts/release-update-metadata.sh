#!/usr/bin/env bash
# Update canonical in-repository release metadata; runtime reads VERSION.
#
# This internal helper performs deterministic file edits. The calling release
# command is responsible for Git-state checks, backup/rollback, checksum
# regeneration, and full validation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ERPNEXT_RELEASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF_USAGE'
Usage:
  scripts/release-update-metadata.sh VERSION TITLE

Examples:
  scripts/release-update-metadata.sh 1.20.0-beta.1 "Release reliability foundation"
  scripts/release-update-metadata.sh 1.20.0 "Engine stability foundation"
EOF_USAGE
}

version="${1:-}"
title="${2:-}"

[[ -n "$version" && -n "$title" ]] || {
  usage
  exit 2
}

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
  || fail "invalid release version: ${version}"

[[ "$title" != *$'\n'* && "$title" != *$'\r'* ]] \
  || fail "release title must be one line"

required_files=(
  VERSION
  README.md
  ROADMAP.md
  TESTING.md
  CHANGELOG.md
  RELEASE-MANIFEST.txt
)

for file in "${required_files[@]}"; do
  [[ -f "${ROOT_DIR}/${file}" ]] \
    || fail "required release metadata file is missing: ${file}"
done

python3 - "$ROOT_DIR" "$version" "$title" <<'PY_UPDATE'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
version = sys.argv[2]
title = sys.argv[3]
tag = f"v{version}"


def write(path: Path, text: str) -> None:
    path.write_text(text)


def replace_one(path: Path, pattern: str, replacement: str, label: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{path}: expected one {label}, found {count}")
    write(path, updated)


write(root / "VERSION", f"{version}\n")

for name in ("README.md", "ROADMAP.md", "TESTING.md"):
    replace_one(
        root / name,
        r'^(\*\*Current release:\*\*) v[0-9A-Za-z.-]+',
        rf'\1 {tag}',
        "Current release banner",
    )

    replace_one(
        root / name,
        r'^(\*\*Current project version:\*\*) v[0-9A-Za-z.-]+',
        rf'\1 {tag}',
        "Current project version",
    )

replace_one(
    root / "RELEASE-MANIFEST.txt",
    r'^(# ERPNext Developer Toolkit Release Manifest )v[0-9A-Za-z.-]+',
    rf'\1{tag}',
    "release manifest header",
)

readme = root / "README.md"
readme_text = readme.read_text()
readme_updated, pin_count = re.subn(
    r'^VERSION="v[0-9A-Za-z.-]+"$',
    f'VERSION="{tag}"',
    readme_text,
    flags=re.MULTILINE,
)
if pin_count > 1:
    raise SystemExit(f"{readme}: expected at most one exact VERSION pin, found {pin_count}")
write(readme, readme_updated)

changelog = root / "CHANGELOG.md"
changelog_text = changelog.read_text()
heading = f"## {tag} - {title}"

matching_headings = re.findall(
    rf'^## {re.escape(tag)}(?:\s|$).*',
    changelog_text,
    flags=re.MULTILINE,
)

if len(matching_headings) > 1:
    raise SystemExit(f"{changelog}: duplicate headings for {tag}")

if matching_headings:
    current_heading = matching_headings[0]
    if current_heading != heading:
        changelog_text = changelog_text.replace(current_heading, heading, 1)

    if not changelog_text.startswith(heading):
        block_pattern = re.compile(
            rf'(^## {re.escape(tag)}(?:\s|$).*?)(?=^## |\Z)',
            flags=re.MULTILINE | re.DOTALL,
        )
        match = block_pattern.search(changelog_text)
        if not match:
            raise SystemExit(f"{changelog}: could not locate existing {tag} block")
        block = match.group(1).rstrip() + "\n\n"
        changelog_text = (
            changelog_text[:match.start()]
            + changelog_text[match.end():]
        )
        changelog_text = block + changelog_text.lstrip()
else:
    block = (
        f"{heading}\n\n"
        "### Added\n\n"
        "- Release notes pending final review.\n\n"
        "### Validation\n\n"
        "- Release validation pending.\n\n"
    )
    changelog_text = block + changelog_text.lstrip()

write(changelog, changelog_text)
PY_UPDATE

echo "Updated release metadata to v${version}"
