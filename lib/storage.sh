# shellcheck shell=bash
# Root storage detection, status, and expansion helpers.
[[ -n "${_ERPNEXT_DEV_STORAGE_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_STORAGE_LOADED=1

# ============================================================
# Generic root storage detection / expansion
# ============================================================

bytes_to_gib() {
  local bytes="${1:-0}"

  if [[ "$bytes" =~ ^[0-9]+$ ]]; then
    awk -v b="$bytes" 'BEGIN { printf "%.0fG\n", b / 1073741824 }'
  else
    echo "0G"
  fi
}

storage_partition_tail_free_bytes() {
  local disk_dev="$1"
  local part_dev="$2"
  local disk_name part_name sector_size disk_sectors part_start part_sectors part_end tail_sectors

  [[ -n "$disk_dev" && -n "$part_dev" ]] || { echo 0; return 0; }

  disk_name="$(basename "$disk_dev")"
  part_name="$(basename "$part_dev")"

  [[ -r "/sys/class/block/${disk_name}/size" && -r "/sys/class/block/${part_name}/start" && -r "/sys/class/block/${part_name}/size" ]] || {
    echo 0
    return 0
  }

  sector_size="$(cat "/sys/class/block/${disk_name}/queue/logical_block_size" 2>/dev/null || echo 512)"
  disk_sectors="$(cat "/sys/class/block/${disk_name}/size" 2>/dev/null || echo 0)"
  part_start="$(cat "/sys/class/block/${part_name}/start" 2>/dev/null || echo 0)"
  part_sectors="$(cat "/sys/class/block/${part_name}/size" 2>/dev/null || echo 0)"

  [[ "$sector_size" =~ ^[0-9]+$ && "$disk_sectors" =~ ^[0-9]+$ && "$part_start" =~ ^[0-9]+$ && "$part_sectors" =~ ^[0-9]+$ ]] || {
    echo 0
    return 0
  }

  part_end=$((part_start + part_sectors))
  if (( disk_sectors > part_end )); then
    tail_sectors=$((disk_sectors - part_end))
  else
    tail_sectors=0
  fi

  echo $((tail_sectors * sector_size))
}

storage_detect_layout() {
  # Generic root storage detector.
  # This intentionally uses the exact proven Ubuntu/LVM repair path when it can
  # derive it safely:
  #   sgdisk -e <disk>; growpart <disk> <part>; pvresize <pv>; lvextend -r <lv>
  # It must not hardcode /dev/vda3 or ubuntu-vg names.
  python3 <<'PY_STORAGE_DETECT'
import os
import re
import shlex
import subprocess
import sys


def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def q(v):
    return "" if v is None else str(v).strip()


def emit(**kv):
    for k, v in kv.items():
        if v is not None and str(v) != "":
            print(f"{k}={v}")


def parse_lsblk_p():
    out = run(["lsblk", "-P", "-o", "NAME,KNAME,PATH,TYPE,PKNAME,PARTN,FSTYPE,MOUNTPOINTS,SIZE"])
    rows = []
    for line in out.splitlines():
        try:
            d = dict(re.findall(r'(\w+)="([^"]*)"', line))
        except Exception:
            d = {}
        if d:
            rows.append(d)
    return rows


def parent_disk_and_partnum(part_dev, rows):
    part_dev = os.path.realpath(part_dev)
    base = os.path.basename(part_dev)
    row = None
    for r in rows:
        names = {r.get("NAME",""), r.get("KNAME",""), os.path.basename(r.get("PATH","") or "")}
        if base in names or os.path.realpath(r.get("PATH","") or "/nonexistent") == part_dev:
            row = r
            break
    partn = q(row.get("PARTN")) if row else ""
    pk = q(row.get("PKNAME")) if row else ""
    disk = f"/dev/{pk}" if pk else ""
    if not partn:
        m = re.search(r'p?(\d+)$', os.path.basename(part_dev))
        if m:
            partn = m.group(1)
    if not disk:
        # /dev/vda3, /dev/sda3, /dev/xvda3
        m = re.match(r'^(/dev/[A-Za-z]+[A-Za-z0-9]*?)(\d+)$', part_dev)
        if m:
            disk = m.group(1)
        # /dev/nvme0n1p3, /dev/mmcblk0p3
        m = re.match(r'^(/dev/(?:nvme\d+n\d+|mmcblk\d+))p(\d+)$', part_dev)
        if m:
            disk = m.group(1)
            partn = partn or m.group(2)
    return disk, partn

root_source = q(run(["findmnt", "-n", "-o", "SOURCE", "/"]).splitlines()[0] if run(["findmnt", "-n", "-o", "SOURCE", "/"]) else "")
root_fs = q(run(["findmnt", "-n", "-o", "FSTYPE", "/"]).splitlines()[0] if run(["findmnt", "-n", "-o", "FSTYPE", "/"]) else "")
if not root_source:
    emit(LAYOUT="unknown", ROOT_SOURCE="unknown", ROOT_FS="unknown", REASON="could not read root mount source")
    sys.exit(0)

root_real = os.path.realpath(root_source)
rows = parse_lsblk_p()
root_row = None
for r in rows:
    mp = r.get("MOUNTPOINTS", "")
    if mp == "/" or "/" in mp.split():
        root_row = r
        break

root_type = q(root_row.get("TYPE")) if root_row else q(run(["lsblk", "-no", "TYPE", root_source]).splitlines()[0] if run(["lsblk", "-no", "TYPE", root_source]) else "")

is_lvm = root_type == "lvm" or root_source.startswith("/dev/mapper/") or root_real.startswith("/dev/dm-")

if is_lvm:
    if not run(["bash", "-lc", "command -v lvs && command -v pvs && command -v vgs"]):
        emit(LAYOUT="unknown", ROOT_SOURCE=root_source, ROOT_FS=root_fs, REASON="LVM tools are not available")
        sys.exit(0)

    # Read LVs, matching either /dev/mapper path, canonical /dev/VG/LV, or dm-* real path.
    lv_out = run(["lvs", "--noheadings", "--separator", "|", "-o", "lv_path,vg_name,devices"])
    lv_path = ""
    vg_name = ""
    devices = ""
    first_lv = None
    for line in lv_out.splitlines():
        parts = [x.strip() for x in line.split("|", 2)]
        if len(parts) < 2:
            continue
        cand_lv, cand_vg = parts[0], parts[1]
        cand_devices = parts[2] if len(parts) > 2 else ""
        if not first_lv:
            first_lv = (cand_lv, cand_vg, cand_devices)
        cand_real = os.path.realpath(cand_lv)
        if cand_lv == root_source or cand_lv == root_real or cand_real == root_real:
            lv_path, vg_name, devices = cand_lv, cand_vg, cand_devices
            break
    if not lv_path and first_lv:
        # If there is only one LV on a simple dev VM, this is usually root.
        lvs_count = len([x for x in lv_out.splitlines() if x.strip()])
        if lvs_count == 1:
            lv_path, vg_name, devices = first_lv
    if not lv_path:
        lv_path = root_source
    if not vg_name:
        vg_name = q(run(["lvs", "--noheadings", "-o", "vg_name", lv_path]).splitlines()[0] if run(["lvs", "--noheadings", "-o", "vg_name", lv_path]) else "")

    # Prefer the PV from LV devices, e.g. /dev/vda3(0). This is the exact value that
    # proved correct manually on Ubuntu Server clones.
    pv_dev = ""
    m = re.search(r'(/dev/[^\s,()]+)(?:\(\d+\))?', devices or "")
    if m:
        pv_dev = m.group(1)

    # Fallback: root lsblk row often has PKNAME=vda3 for LVM roots.
    if not pv_dev and root_row and q(root_row.get("PKNAME")):
        maybe = "/dev/" + q(root_row.get("PKNAME"))
        if os.path.exists(maybe):
            pv_dev = maybe

    # Fallback: if the VG has exactly one PV, use it.
    if not pv_dev and vg_name:
        pv_out = run(["pvs", "--noheadings", "--separator", "|", "-o", "pv_name,vg_name"])
        pvs = []
        for line in pv_out.splitlines():
            parts = [x.strip() for x in line.split("|")]
            if len(parts) >= 2 and parts[1] == vg_name:
                pvs.append(re.sub(r'\(\d+\)$', '', parts[0]))
        if len(set(pvs)) == 1:
            pv_dev = sorted(set(pvs))[0]

    disk_dev = ""
    part_num = ""
    if pv_dev:
        pv_dev = os.path.realpath(pv_dev)
        disk_dev, part_num = parent_disk_and_partnum(pv_dev, rows)

    # This is the supported automatic LVM path. Even if disk/part cannot be derived,
    # lvextend can still consume existing VG free space safely.
    emit(
        LAYOUT="lvm",
        ROOT_SOURCE=root_source,
        ROOT_FS=root_fs,
        LV_PATH=lv_path,
        VG_NAME=vg_name,
        PV_DEV=pv_dev,
        PART_DEV=pv_dev,
        DISK_DEV=disk_dev,
        PART_NUM=part_num,
        REASON="" if pv_dev else "could not identify LVM PV; only existing VG free space can be used automatically",
    )
    sys.exit(0)

# Direct root partition case.
part_dev = root_real
if root_type == "part" or (root_row and root_row.get("TYPE") == "part"):
    disk_dev, part_num = parent_disk_and_partnum(part_dev, rows)
    emit(LAYOUT="partition", ROOT_SOURCE=part_dev, ROOT_FS=root_fs, PART_DEV=part_dev, DISK_DEV=disk_dev, PART_NUM=part_num)
    sys.exit(0)

emit(LAYOUT="unknown", ROOT_SOURCE=root_source, ROOT_FS=root_fs, REASON="root device is not a supported partition or LVM layout")
PY_STORAGE_DETECT
  return 0
}

storage_eval() {
  local data
  local layout="" root_source="" root_fs="" disk_dev="" part_dev="" pv_dev="" lv_path="" vg_name="" reason=""
  local root_bytes="0" disk_bytes="0" part_bytes="0" vg_free_bytes="0" tail_free_bytes="0" can_expand="no"

  data="$(storage_detect_layout 2>/dev/null || true)"
  [[ -n "$data" ]] || {
    printf 'LAYOUT=unknown\nCAN_EXPAND=no\nREASON=storage layout could not be detected\n'
    return 0
  }

  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_SOURCE) root_source="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      PV_DEV) pv_dev="$v" ;;
      LV_PATH) lv_path="$v" ;;
      VG_NAME) vg_name="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  root_bytes="$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2+0}' || echo 0)"

  if [[ -n "$disk_dev" ]]; then
    disk_bytes="$(lsblk -bndo SIZE "$disk_dev" 2>/dev/null | awk 'NR==1 {print $1+0}' || echo 0)"
  fi

  if [[ -n "$part_dev" ]]; then
    part_bytes="$(lsblk -bndo SIZE "$part_dev" 2>/dev/null | awk 'NR==1 {print $1+0}' || echo 0)"
  fi

  if [[ -n "$disk_dev" && -n "$part_dev" ]]; then
    tail_free_bytes="$(storage_partition_tail_free_bytes "$disk_dev" "$part_dev")"
  fi

  if [[ "$layout" == "lvm" ]]; then
    if [[ -z "$vg_name" && -n "$lv_path" ]]; then
      vg_name="$(lvs --noheadings -o vg_name "$lv_path" 2>/dev/null | awk 'NF {print $1; exit}' || true)"
    fi

    if [[ -n "$vg_name" ]]; then
      vg_free_bytes="$(vgs --noheadings --units b --nosuffix -o vg_free "$vg_name" 2>/dev/null | awk 'NF {printf "%.0f", $1+0; exit}' || echo 0)"
    fi
  fi

  # Expansion is recommended only if there is usable free space:
  # 1) LVM VG already has free extents, OR
  # 2) the root partition/PV has free space after it at the end of the disk.
  # Do not compare whole disk size to partition size. That falsely counts /boot,
  # BIOS partitions, and earlier partition offsets as growable free space.
  if [[ "$layout" == "lvm" ]]; then
    if [[ "$vg_free_bytes" =~ ^[0-9]+$ ]] && (( vg_free_bytes > 1073741824 )); then
      can_expand="yes"
      reason="LVM has free space available"
    elif [[ "$tail_free_bytes" =~ ^[0-9]+$ ]] && (( tail_free_bytes > 1073741824 )); then
      can_expand="yes"
      reason="LVM physical partition can grow into free disk space"
    else
      reason="root storage already appears to use available LVM/disk space"
    fi
  elif [[ "$layout" == "partition" ]]; then
    if [[ "$tail_free_bytes" =~ ^[0-9]+$ ]] && (( tail_free_bytes > 1073741824 )); then
      can_expand="yes"
      reason="root partition can grow into free disk space"
    else
      reason="root partition already appears to use available disk space"
    fi
  else
    can_expand="no"
    reason="${reason:-storage layout is not supported for automatic expansion}"
  fi

  printf '%s\n' "$data"
  printf 'ROOT_BYTES=%s\nDISK_BYTES=%s\nPART_BYTES=%s\nVG_FREE_BYTES=%s\nTAIL_FREE_BYTES=%s\nCAN_EXPAND=%s\nREASON=%s\n' \
    "$root_bytes" "$disk_bytes" "$part_bytes" "$vg_free_bytes" "$tail_free_bytes" "$can_expand" "$reason"
}
show_storage_status() {
  local data layout root_source root_fs disk_dev part_dev lv_path root_bytes disk_bytes vg_free_bytes tail_free_bytes can_expand reason

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_SOURCE) root_source="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      LV_PATH) lv_path="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      DISK_BYTES) disk_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      TAIL_FREE_BYTES) tail_free_bytes="$v" ;;
      CAN_EXPAND) can_expand="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  echo
  echo "============================================================"
  echo "Root Storage Status"
  echo "============================================================"
  status_line "Layout" "INFO" "${layout:-unknown}"
  status_line "Root filesystem" "INFO" "${root_source:-unknown} (${root_fs:-unknown})"
  [[ -n "${disk_dev:-}" ]] && status_line "Backing disk" "INFO" "${disk_dev} ($(bytes_to_gib "${disk_bytes:-0}"))"
  [[ -n "${part_dev:-}" ]] && status_line "Root partition/PV" "INFO" "${part_dev}"
  [[ -n "${lv_path:-}" ]] && status_line "Root LV" "INFO" "${lv_path}"
  if [[ "${layout:-}" == "lvm" && "${vg_free_bytes:-0}" =~ ^[0-9]+$ && "${vg_free_bytes:-0}" -gt 0 ]]; then
    status_line "VG free" "INFO" "$(bytes_to_gib "${vg_free_bytes:-0}")"
  fi
  if [[ "${tail_free_bytes:-0}" =~ ^[0-9]+$ && "${tail_free_bytes:-0}" -gt 0 ]]; then
    status_line "Growable disk tail" "INFO" "$(bytes_to_gib "${tail_free_bytes:-0}")"
  fi
  status_line "Root size" "INFO" "$(bytes_to_gib "${root_bytes:-0}")"

  if [[ "${can_expand:-no}" == "yes" ]]; then
    status_line "Expansion" "WARN" "recommended"
    echo
    echo "Run: $(toolkit_cmd expand-root-storage)"
  elif [[ "${layout:-unknown}" == "unknown" ]]; then
    status_line "Expansion" "WARN" "not automatic"
    [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
  else
    status_line "Expansion" "OK" "not needed"
  fi
  echo "============================================================"
}

ensure_storage_tools() {
  local packages=()

  command -v growpart >/dev/null 2>&1 || packages+=(cloud-guest-utils)
  command -v sgdisk >/dev/null 2>&1 || packages+=(gdisk)

  if [[ "${#packages[@]}" -gt 0 ]]; then
    log "Installing storage resize tools"
    $SUDO apt-get update
    $SUDO apt-get install -y "${packages[@]}"
  fi
}

expand_root_storage() {
  require_sudo

  local data layout root_fs lv_path pv_dev part_dev disk_dev part_num vg_free_bytes tail_free_bytes can_expand reason

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      LAYOUT) layout="$v" ;;
      ROOT_FS) root_fs="$v" ;;
      LV_PATH) lv_path="$v" ;;
      PV_DEV) pv_dev="$v" ;;
      PART_DEV) part_dev="$v" ;;
      DISK_DEV) disk_dev="$v" ;;
      PART_NUM) part_num="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      TAIL_FREE_BYTES) tail_free_bytes="$v" ;;
      CAN_EXPAND) can_expand="$v" ;;
      REASON) reason="$v" ;;
    esac
  done <<< "$data"

  echo
  echo "============================================================"
  echo "Expand Root Storage"
  echo "============================================================"

  if [[ "${can_expand:-no}" != "yes" ]]; then
    if [[ "${layout:-unknown}" == "unknown" ]]; then
      status_line "Storage" "WARN" "not automatic"
      [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
      echo "No changes made."
    else
      status_line "Storage" "OK" "no expansion needed"
      [[ -n "${reason:-}" ]] && echo "${reason}"
    fi
    echo "============================================================"
    return 0
  fi

  if [[ "${layout:-unknown}" != "lvm" && "${layout:-unknown}" != "partition" ]]; then
    status_line "Storage" "WARN" "layout not supported"
    [[ -n "${reason:-}" ]] && echo "Reason: ${reason}"
    echo "No changes made."
    echo "============================================================"
    return 0
  fi

  if [[ "$layout" != "lvm" && ( -z "${disk_dev:-}" || -z "${part_num:-}" || -z "${part_dev:-}" ) ]]; then
    status_line "Storage" "WARN" "could not identify disk/partition safely"
    echo "No changes made."
    echo "============================================================"
    return 0
  fi

  [[ -n "${disk_dev:-}" ]] && status_line "Target disk" "INFO" "$disk_dev"
  [[ -n "${part_dev:-}" ]] && status_line "Target partition" "INFO" "$part_dev"
  [[ -n "${lv_path:-}" ]] && status_line "Target LV" "INFO" "$lv_path"
  status_line "Layout" "INFO" "$layout"

  if [[ "${EXPAND_ROOT_CONFIRMED:-0}" != "1" && "$ASSUME_YES" -ne 1 ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Expand root storage now? [Y/n]: " reply
      reply="${reply:-Y}"
      if ! [[ "$reply" =~ ^[Yy]$ ]]; then
        warn "Storage expansion skipped."
        echo "============================================================"
        return 0
      fi
    fi
  fi

  ensure_storage_tools

  if [[ "$layout" == "lvm" ]]; then
    if ! command -v pvresize >/dev/null 2>&1 || ! command -v lvextend >/dev/null 2>&1; then
      log "Installing LVM tools"
      $SUDO apt-get install -y lvm2
    fi

    if [[ -n "${disk_dev:-}" && -n "${part_num:-}" && -n "${part_dev:-}" && "${tail_free_bytes:-0}" =~ ^[0-9]+$ && "${tail_free_bytes:-0}" -gt 1073741824 ]]; then
      log "Growing partition ${part_dev}"
      if command -v sgdisk >/dev/null 2>&1; then
        $SUDO sgdisk -e "$disk_dev" >/dev/null 2>&1 || true
      fi
      $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
      if ! $SUDO growpart "$disk_dev" "$part_num"; then
        warn "growpart did not report a clean change. Continuing with LVM resize if possible."
      fi
      $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
      log "Growing LVM physical volume"
      $SUDO pvresize "${pv_dev:-$part_dev}"
    elif [[ "${vg_free_bytes:-0}" =~ ^[0-9]+$ && "${vg_free_bytes:-0}" -gt 1073741824 ]]; then
      warn "No growable disk tail detected. Using existing VG free space only."
    else
      warn "Could not safely grow the LVM physical partition. Using existing VG free space only."
    fi

    log "Extending root logical volume"
    $SUDO lvextend -r -l +100%FREE "$lv_path"
  else
    if [[ ! "${tail_free_bytes:-0}" =~ ^[0-9]+$ || "${tail_free_bytes:-0}" -le 1073741824 ]]; then
      status_line "Storage" "OK" "no partition growth needed"
      echo "Root partition already appears to use available disk space."
      echo "============================================================"
      return 0
    fi

    log "Growing partition ${part_dev}"
    if command -v sgdisk >/dev/null 2>&1; then
      $SUDO sgdisk -e "$disk_dev" >/dev/null 2>&1 || true
    fi
    $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true

    if ! $SUDO growpart "$disk_dev" "$part_num"; then
      warn "growpart did not report a clean change. Continuing with filesystem resize if possible."
    fi
    $SUDO partprobe "$disk_dev" >/dev/null 2>&1 || true
    case "$root_fs" in
      ext2|ext3|ext4)
        log "Growing ${root_fs} filesystem"
        $SUDO resize2fs "$part_dev"
        ;;
      xfs)
        log "Growing XFS filesystem"
        $SUDO xfs_growfs /
        ;;
      *)
        warn "Filesystem ${root_fs:-unknown} is not supported for automatic resize."
        warn "Partition was grown if possible, but filesystem was not changed."
        ;;
    esac
  fi

  ok "Root storage expansion completed"
  show_storage_status
}

storage_debug() {
  echo
  echo "============================================================"
  echo "Storage Debug"
  echo "============================================================"
  echo "findmnt:"
  findmnt -no SOURCE,FSTYPE,SIZE,AVAIL / || true
  echo
  echo "lsblk:"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,PKNAME,PARTN || true
  echo
  echo "lvs:"
  sudo lvs -o lv_path,vg_name,lv_size,devices 2>/dev/null || true
  echo
  echo "pvs:"
  sudo pvs -o pv_name,vg_name,pv_size,pv_free 2>/dev/null || true
  echo
  echo "vgs:"
  sudo vgs -o vg_name,vg_size,vg_free 2>/dev/null || true
  echo
  echo "detector:"
  storage_detect_layout || true
  echo
  echo "evaluation:"
  storage_eval || true
  echo "============================================================"
}

verify_storage() {
  local free_gb
  free_gb="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}' 2>/dev/null || echo 0)"

  show_storage_status

  if [[ "$free_gb" -lt 30 ]]; then
    warn "Root free space is ${free_gb}G. ERPNext can install, but 60G+ is recommended."
    return 1
  fi

  ok "Root free space: ${free_gb}G"
}

maybe_offer_root_storage_expansion() {
  local data can_expand root_bytes disk_bytes vg_free_bytes layout reply

  data="$(storage_eval)"
  while IFS='=' read -r k v; do
    case "$k" in
      CAN_EXPAND) can_expand="$v" ;;
      ROOT_BYTES) root_bytes="$v" ;;
      DISK_BYTES) disk_bytes="$v" ;;
      VG_FREE_BYTES) vg_free_bytes="$v" ;;
      LAYOUT) layout="$v" ;;
    esac
  done <<< "$data"

  if [[ "${can_expand:-no}" != "yes" ]]; then
    return 0
  fi

  echo
  if [[ "${disk_bytes:-0}" =~ ^[0-9]+$ && "${disk_bytes:-0}" -gt 0 ]]; then
    echo "Storage: root uses $(bytes_to_gib "${root_bytes:-0}") of $(bytes_to_gib "${disk_bytes:-0}") disk."
  elif [[ "${layout:-}" == "lvm" && "${vg_free_bytes:-0}" =~ ^[0-9]+$ && "${vg_free_bytes:-0}" -gt 0 ]]; then
    echo "Storage: root can use $(bytes_to_gib "${vg_free_bytes:-0}") free LVM space."
  else
    echo "Storage expansion is available."
  fi

  if [[ "${AUTO_EXPAND_ROOT:-prompt}" == "false" ]]; then
    warn "Root storage expansion skipped by AUTO_EXPAND_ROOT=false."
    return 0
  fi

  if [[ "${AUTO_EXPAND_ROOT:-prompt}" == "true" || "$ASSUME_YES" -eq 1 ]]; then
    EXPAND_ROOT_CONFIRMED=1 expand_root_storage
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "Expand root storage now? [Y/n]: " reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      EXPAND_ROOT_CONFIRMED=1 expand_root_storage
    else
      warn "Storage expansion skipped."
    fi
  fi
}
