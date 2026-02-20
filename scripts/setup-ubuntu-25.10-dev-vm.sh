#!/usr/bin/env bash
set -euo pipefail

VM_OS="ubuntu"
VM_RELEASE="25.10"
VM_USER="ilma4"
VM_PASSWORD="1234"
VM_HOSTNAME="ubuntu-dev-vm"
VM_DISK_SIZE="100G"
VM_RAM="16G"
VM_CPU_CORES="8"
VM_SSH_PORT="22222"
VM_SPICE_PORT=""
SSH_WAIT_TIMEOUT_SECONDS=$((15 * 60))
INSTALL_WAIT_TIMEOUT_SECONDS=$((2 * 60 * 60))
WORKDIR="${PWD}/.vm/${VM_OS}-${VM_RELEASE}-dev"

usage() {
  cat <<'EOF'
Usage: setup-ubuntu-25.10-dev-vm.sh [--workdir DIR] [--ssh-port PORT] [--spice-port PORT] [--ssh-timeout-seconds SECONDS]

Creates an unattended Ubuntu 25.10 desktop VM using quickget/quickemu and cloud-init.
EOF
}

log() {
  printf '[setup-ubuntu-vm] %s\n' "$*"
}

die() {
  printf '[setup-ubuntu-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Missing required command: ${cmd}"
  fi
}

generate_password_hash() {
  local password="$1"
  local hash=""

  if hash="$(openssl passwd -6 "$password" 2>/dev/null)"; then
    if [[ "$hash" == \$6\$* ]]; then
      printf '%s\n' "$hash"
      return 0
    fi
  fi

  if command -v nix >/dev/null 2>&1; then
    hash="$(
      nix shell nixpkgs#openssl --command openssl passwd -6 "$password" 2>/dev/null | head -n1 || true
    )"
    if [[ "$hash" == \$6\$* ]]; then
      printf '%s\n' "$hash"
      return 0
    fi
  fi

  die "Unable to generate a SHA-512 password hash; install GNU/OpenSSL with '-6' support"
}

upsert_conf_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"

  awk -v key="$key" -v value="$value" '
    BEGIN { updated = 0 }
    $0 ~ ("^" key "=") {
      if (updated == 0) {
        print key "=" value
        updated = 1
      }
      next
    }
    { print }
    END {
      if (updated == 0) {
        print key "=" value
      }
    }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workdir)
        [[ $# -ge 2 ]] || die "--workdir requires a value"
        WORKDIR="$2"
        shift 2
        ;;
      --ssh-port)
        [[ $# -ge 2 ]] || die "--ssh-port requires a value"
        VM_SSH_PORT="$2"
        shift 2
        ;;
      --ssh-timeout-seconds)
        [[ $# -ge 2 ]] || die "--ssh-timeout-seconds requires a value"
        SSH_WAIT_TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --spice-port)
        [[ $# -ge 2 ]] || die "--spice-port requires a value"
        VM_SPICE_PORT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

quickemu_arch_for_host() {
  local host_arch
  host_arch="$(uname -m)"
  case "$host_arch" in
    arm64|aarch64)
      printf '%s\n' "aarch64"
      ;;
    *)
      printf '%s\n' "x86_64"
      ;;
  esac
}

pick_free_tcp_port() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
    return 0
  fi

  local port
  for port in $(seq 20000 65000); do
    if ! (echo >/dev/tcp/127.0.0.1/"${port}") >/dev/null 2>&1; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  return 1
}

ensure_quickemu_stat_compat() {
  if [[ "$(uname -s)" != "Darwin" ]] || command -v gstat >/dev/null 2>&1; then
    return 0
  fi

  local shim_dir="${WORKDIR}/.shim-bin"
  mkdir -p "$shim_dir"

  cat >"${shim_dir}/gstat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 2 && "$1" == "-c%s" ]]; then
  stat -f "%z" "$2"
  exit 0
fi

if [[ $# -eq 3 && "$1" == "-c" && "$2" == "%A" ]]; then
  stat -f "%Sp" "$3"
  exit 0
fi

echo "gstat shim: unsupported arguments: $*" >&2
exit 1
EOF

  chmod +x "${shim_dir}/gstat"
  PATH="${shim_dir}:${PATH}"
}

wait_for_vm_exit_if_backgrounded() {
  local pid_file="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  local vm_pid=""
  local try

  # On macOS quickemu may daemonize and return immediately; wait for PID file.
  for try in $(seq 1 20); do
    if [[ -f "$pid_file" ]]; then
      vm_pid="$(tr -d '[:space:]' < "$pid_file" || true)"
      break
    fi
    sleep 1
  done

  if [[ -z "$vm_pid" || ! "$vm_pid" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if ! kill -0 "$vm_pid" >/dev/null 2>&1; then
    return 0
  fi

  log "Install VM started in background (pid ${vm_pid}), waiting for it to finish"
  while kill -0 "$vm_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      return 1
    fi
    sleep 10
  done

  return 0
}

send_qemu_monitor_cmd() {
  local monitor_socket="$1"
  local cmd="$2"
  local socket_path="$monitor_socket"
  local tmp_link_dir=""
  local tmp_link_path=""

  [[ -S "$monitor_socket" ]] || return 1

  # AF_UNIX paths are limited (typically 104-108 bytes), so shorten if needed.
  if (( ${#socket_path} > 100 )); then
    tmp_link_dir="$(mktemp -d)"
    tmp_link_path="${tmp_link_dir}/m.sock"
    ln -s "$monitor_socket" "$tmp_link_path"
    socket_path="$tmp_link_path"
  fi

  if ! python3 - <<'PY' "$socket_path" "$cmd"
import socket
import sys

sock_path = sys.argv[1]
command = sys.argv[2]

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2.0)
try:
    sock.connect(sock_path)
except OSError:
    sys.exit(1)
try:
    try:
        sock.recv(4096)
    except Exception:
        pass
    sock.sendall((command + "\n").encode())
finally:
    sock.close()
PY
  then
    if [[ -n "$tmp_link_dir" ]]; then
      rm -rf "$tmp_link_dir"
    fi
    return 1
  fi

  if [[ -n "$tmp_link_dir" ]]; then
    rm -rf "$tmp_link_dir"
  fi
}

wait_for_install_completion() {
  local pid_file="$1"
  local monitor_socket="$2"
  local ssh_key="$3"
  local disk_img="$4"
  local timeout_seconds="$5"
  local deadline=$((SECONDS + timeout_seconds))
  local vm_pid=""
  local install_hostname=""
  local disk_mb="0"
  local last_disk_mb="-1"
  local last_disk_change=$SECONDS

  # If quickemu is blocking (Linux), PID file may be absent by the time we get here.
  if [[ -f "$pid_file" ]]; then
    vm_pid="$(tr -d '[:space:]' < "$pid_file" || true)"
  fi
  if [[ -z "$vm_pid" || ! "$vm_pid" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if ! kill -0 "$vm_pid" >/dev/null 2>&1; then
    return 0
  fi

  log "Install VM started in background (pid ${vm_pid}), waiting for completion"
  while kill -0 "$vm_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      return 1
    fi

    disk_mb="$(du -m "$disk_img" 2>/dev/null | awk '{print $1}' || true)"
    if [[ "$disk_mb" =~ ^[0-9]+$ ]]; then
      if [[ "$disk_mb" != "$last_disk_mb" ]]; then
        last_disk_mb="$disk_mb"
        last_disk_change=$SECONDS
      fi
    fi

    install_hostname="$(
      ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -i "$ssh_key" \
        -p "$VM_SSH_PORT" \
        "${VM_USER}@127.0.0.1" 'hostname' 2>/dev/null || true
    )"

    if [[ "$install_hostname" == "$VM_HOSTNAME" ]]; then
      log "Install VM reached installed system state, requesting poweroff"
      send_qemu_monitor_cmd "$monitor_socket" "system_powerdown" || true

      local poweroff_deadline=$((SECONDS + 180))
      while kill -0 "$vm_pid" >/dev/null 2>&1 && (( SECONDS < poweroff_deadline )); do
        sleep 5
      done

      if kill -0 "$vm_pid" >/dev/null 2>&1; then
        log "Install VM did not power off in time, forcing quit"
        send_qemu_monitor_cmd "$monitor_socket" "quit" || true
      fi
    fi

    # Fallback for cases where installer idles indefinitely in a post-install state.
    if [[ "$disk_mb" =~ ^[0-9]+$ ]] && (( disk_mb >= 4000 )) && (( SECONDS - last_disk_change >= 300 )); then
      log "Install VM appears idle after disk growth, forcing quit"
      send_qemu_monitor_cmd "$monitor_socket" "quit" || true
    fi

    sleep 5
  done

  return 0
}

find_base_conf() {
  local target="${WORKDIR}/${VM_OS}-${VM_RELEASE}.conf"
  if [[ -f "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  local conf
  conf="$(find "$WORKDIR" -maxdepth 1 -type f -name "${VM_OS}-${VM_RELEASE}*.conf" ! -name '*-autoinstall.conf' | head -n1 || true)"
  [[ -n "$conf" ]] || die "Unable to find quickget config in ${WORKDIR}"
  printf '%s\n' "$conf"
}

read_conf_var() {
  local conf="$1"
  local key="$2"
  bash -c '
    set -euo pipefail
    source "$1"
    case "$2" in
      iso) printf "%s\n" "${iso:-}" ;;
      disk_img) printf "%s\n" "${disk_img:-}" ;;
      *) exit 2 ;;
    esac
  ' _ "$conf" "$key"
}

to_abs_path() {
  local value="$1"
  local base="$2"
  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$base" "$value"
  fi
}

find_iso_entry() {
  local iso_path="$1"
  local kind="$2"
  local pattern=""

  if [[ "$kind" == "kernel" ]]; then
    pattern='^(\./)?casper/(vmlinuz|hwe-vmlinuz|vmlinuz\.efi|linux)$'
  else
    pattern='^(\./)?casper/(initrd|hwe-initrd|initrd\.lz)$'
  fi

  bsdtar -tf "$iso_path" | grep -E -m1 "$pattern" || true
}

ensure_no_spaces() {
  local path_value="$1"
  if [[ "$path_value" == *" "* ]]; then
    die "Path contains spaces and cannot be passed via quickemu extra_args: ${path_value}"
  fi
}

wait_for_ssh() {
  local ssh_key="$1"
  local known_hosts="$2"
  local quickemu_pid="$3"
  local vm_pid_file="$4"
  local deadline=$((SECONDS + SSH_WAIT_TIMEOUT_SECONDS))
  local startup_deadline=$((SECONDS + 30))
  local vm_pid=""
  local vm_alive=0

  while (( SECONDS < deadline )); do
    vm_alive=0
    vm_pid=""
    if [[ -f "$vm_pid_file" ]]; then
      vm_pid="$(tr -d '[:space:]' < "$vm_pid_file" || true)"
      if [[ "$vm_pid" =~ ^[0-9]+$ ]] && kill -0 "$vm_pid" >/dev/null 2>&1; then
        vm_alive=1
      fi
    fi

    if [[ $vm_alive -eq 0 ]] && kill -0 "$quickemu_pid" >/dev/null 2>&1; then
      vm_alive=1
    fi

    if [[ $vm_alive -eq 0 ]]; then
      if (( SECONDS >= startup_deadline )); then
        return 2
      fi
      sleep 1
      continue
    fi

    if ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$known_hosts" \
      -o ConnectTimeout=5 \
      -i "$ssh_key" \
      -p "$VM_SSH_PORT" \
      "${VM_USER}@127.0.0.1" "echo ok" >/dev/null 2>&1; then
      return 0
    fi

    sleep 5
  done

  return 1
}

main() {
  parse_args "$@"

  require_cmd quickget
  require_cmd quickemu
  require_cmd cloud-localds
  require_cmd openssl
  require_cmd ssh
  require_cmd ssh-keygen
  require_cmd bsdtar

  [[ "$VM_SSH_PORT" =~ ^[0-9]+$ ]] || die "--ssh-port must be numeric"
  if [[ -n "$VM_SPICE_PORT" ]]; then
    [[ "$VM_SPICE_PORT" =~ ^[0-9]+$ ]] || die "--spice-port must be numeric"
  else
    VM_SPICE_PORT="$(pick_free_tcp_port)" || die "Unable to pick a free TCP port for SPICE"
  fi
  [[ "$SSH_WAIT_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "--ssh-timeout-seconds must be numeric"

  mkdir -p "$WORKDIR"
  WORKDIR="$(cd "$WORKDIR" && pwd)"
  ensure_quickemu_stat_compat

  log "Downloading Ubuntu ${VM_RELEASE} desktop ISO with quickget"
  (
    cd "$WORKDIR"
    quickget "$VM_OS" "$VM_RELEASE"
  )

  local base_conf
  local conf_dir
  local iso_raw
  local disk_img_raw
  local iso_path
  local disk_img_path
  local vm_dir
  local vm_name
  local install_conf
  local ssh_key
  local ssh_pub
  local password_hash
  local user_data
  local meta_data
  local seed_iso
  local kernel_entry
  local initrd_entry
  local install_kernel
  local install_initrd
  local install_extra_args
  local install_log
  local run_log
  local run_pid
  local run_pid_file
  local known_hosts
  local ssh_output
  local vm_arch
  local install_vm_name
  local install_pid_file
  local install_monitor_socket

  base_conf="$(find_base_conf)"
  conf_dir="$(cd "$(dirname "$base_conf")" && pwd)"

  iso_raw="$(read_conf_var "$base_conf" iso)"
  disk_img_raw="$(read_conf_var "$base_conf" disk_img)"

  [[ -n "$disk_img_raw" ]] || die "disk_img path is missing in ${base_conf}"

  if [[ -z "$iso_raw" ]]; then
    iso_path="$(find "$WORKDIR" -maxdepth 3 -type f -name '*.iso' ! -name 'autoinstall-*.iso' | head -n1 || true)"
  else
    iso_path="$(to_abs_path "$iso_raw" "$conf_dir")"
  fi

  [[ -n "$iso_path" ]] || die "Installer ISO path could not be determined"
  disk_img_path="$(to_abs_path "$disk_img_raw" "$conf_dir")"
  vm_dir="$(dirname "$disk_img_path")"
  vm_name="$(basename "${base_conf%.conf}")"

  [[ -f "$iso_path" ]] || die "Installer ISO not found: ${iso_path}"

  mkdir -p "$vm_dir"
  vm_arch="$(quickemu_arch_for_host)"

  if [[ -f "$disk_img_path" ]]; then
    log "Removing existing disk image for a clean unattended install: ${disk_img_path}"
    rm -f "$disk_img_path"
  fi

  # Reset EFI vars to avoid stale arch-specific OVMF variable-store sizes.
  rm -f "${vm_dir}/OVMF_VARS.fd" "${vm_dir}/OVMF_VARS_4M.fd" "${vm_dir}/${vm_name}-vars.fd"
  rm -f "${vm_dir}/${vm_name}.pid" "${vm_dir}/${vm_name}.ports" "${vm_dir}/${vm_name}.spice"
  rm -f "${vm_dir}/${vm_name}-autoinstall.pid" "${vm_dir}/${vm_name}-autoinstall.ports" "${vm_dir}/${vm_name}-autoinstall.spice"

  ssh_key="${vm_dir}/autoinstall-ed25519"
  if [[ ! -f "$ssh_key" ]]; then
    log "Generating SSH key for verification"
    ssh-keygen -q -t ed25519 -N "" -f "$ssh_key" -C "quickemu-${vm_name}-autoinstall"
  fi
  ssh_pub="$(<"${ssh_key}.pub")"

  password_hash="$(generate_password_hash "$VM_PASSWORD")"

  user_data="${vm_dir}/autoinstall-user-data"
  meta_data="${vm_dir}/autoinstall-meta-data"
  seed_iso="${vm_dir}/autoinstall-seed.iso"

  cat >"$meta_data" <<EOF
instance-id: ${vm_name}-autoinstall
local-hostname: ${VM_HOSTNAME}
EOF

  cat >"$user_data" <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${VM_HOSTNAME}
    username: ${VM_USER}
    password: '${password_hash}'
  ssh:
    install-server: true
    allow-pw: true
    authorized-keys:
      - ${ssh_pub}
  packages:
    - openssh-server
  late-commands:
    - curtin in-target --target=/target -- /bin/bash -c "echo '${VM_USER}:${VM_PASSWORD}' | chpasswd"
    - curtin in-target --target=/target -- /bin/bash -c "sed -Ei 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
    - curtin in-target --target=/target -- /bin/bash -c "sed -Ei 's/^#?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config"
    - curtin in-target --target=/target -- systemctl enable ssh
  shutdown: reboot
EOF

  log "Creating cloud-init seed ISO"
  cloud-localds "$seed_iso" "$user_data" "$meta_data"

  kernel_entry="$(find_iso_entry "$iso_path" kernel)"
  initrd_entry="$(find_iso_entry "$iso_path" initrd)"
  [[ -n "$kernel_entry" ]] || die "Unable to find kernel in ${iso_path}"
  [[ -n "$initrd_entry" ]] || die "Unable to find initrd in ${iso_path}"

  install_kernel="${vm_dir}/autoinstall-vmlinuz"
  install_initrd="${vm_dir}/autoinstall-initrd"
  bsdtar -xOf "$iso_path" "$kernel_entry" >"$install_kernel"
  bsdtar -xOf "$iso_path" "$initrd_entry" >"$install_initrd"

  ensure_no_spaces "$install_kernel"
  ensure_no_spaces "$install_initrd"

  upsert_conf_value "$base_conf" "disk_size" "\"${VM_DISK_SIZE}\""
  upsert_conf_value "$base_conf" "ram" "\"${VM_RAM}\""
  upsert_conf_value "$base_conf" "cpu_cores" "${VM_CPU_CORES}"
  upsert_conf_value "$base_conf" "arch" "\"${vm_arch}\""
  upsert_conf_value "$base_conf" "ssh_port" "${VM_SSH_PORT}"
  upsert_conf_value "$base_conf" "spice_port" "${VM_SPICE_PORT}"
  upsert_conf_value "$base_conf" "display" "\"none\""
  upsert_conf_value "$base_conf" "viewer" "\"none\""
  upsert_conf_value "$base_conf" "iso" "\"\""
  upsert_conf_value "$base_conf" "fixed_iso" "\"\""
  upsert_conf_value "$base_conf" "extra_args" "\"\""

  install_conf="${WORKDIR}/${vm_name}-autoinstall.conf"
  cp "$base_conf" "$install_conf"
  install_vm_name="$(basename "${install_conf%.conf}")"
  install_pid_file="${vm_dir}/${install_vm_name}.pid"
  install_monitor_socket="${vm_dir}/${install_vm_name}-monitor.socket"
  rm -f "$install_pid_file"

  install_extra_args="-kernel ${install_kernel} -initrd ${install_initrd} -append autoinstall -no-reboot"
  upsert_conf_value "$install_conf" "iso" "\"${iso_path}\""
  upsert_conf_value "$install_conf" "fixed_iso" "\"${seed_iso}\""
  upsert_conf_value "$install_conf" "arch" "\"${vm_arch}\""
  upsert_conf_value "$install_conf" "spice_port" "${VM_SPICE_PORT}"
  upsert_conf_value "$install_conf" "extra_args" "\"${install_extra_args}\""

  install_log="${vm_dir}/autoinstall-install.log"
  log "Running unattended installation (this can take a while)"
  if ! quickemu --vm "$install_conf" >"$install_log" 2>&1; then
    tail -n 60 "$install_log" >&2 || true
    die "Install stage failed. Full log: ${install_log}"
  fi
  if ! wait_for_install_completion "$install_pid_file" "$install_monitor_socket" "$ssh_key" "$disk_img_path" "$INSTALL_WAIT_TIMEOUT_SECONDS"; then
    tail -n 60 "$install_log" >&2 || true
    die "Timed out waiting for unattended install VM to finish. Full log: ${install_log}"
  fi

  run_log="${vm_dir}/autoinstall-run.log"
  known_hosts="${vm_dir}/autoinstall-known_hosts"
  : >"$known_hosts"
  run_pid_file="${vm_dir}/${vm_name}.pid"
  rm -f "$run_pid_file"

  log "Launching installed VM"
  quickemu --vm "$base_conf" >"$run_log" 2>&1 &
  run_pid=$!

  log "Waiting for SSH on localhost:${VM_SSH_PORT}"
  local ssh_wait_rc=0
  wait_for_ssh "$ssh_key" "$known_hosts" "$run_pid" "$run_pid_file" || ssh_wait_rc=$?
  if [[ $ssh_wait_rc -ne 0 ]]; then
    if [[ $ssh_wait_rc -eq 2 ]]; then
      tail -n 60 "$run_log" >&2 || true
      die "VM exited before SSH became ready. Full log: ${run_log}"
    fi
    tail -n 60 "$run_log" >&2 || true
    die "Timed out waiting for SSH. Full log: ${run_log}"
  fi

  ssh_output="$(
    ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$known_hosts" \
      -o ConnectTimeout=5 \
      -i "$ssh_key" \
      -p "$VM_SSH_PORT" \
      "${VM_USER}@127.0.0.1" 'hostname && uname -sr'
  )"

  log "SSH verification succeeded:"
  printf '%s\n' "$ssh_output"
  log "VM is running in background (pid ${run_pid})"
  log "Connect with: ssh -i ${ssh_key} -p ${VM_SSH_PORT} ${VM_USER}@127.0.0.1"
}

main "$@"
