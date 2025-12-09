#!/usr/bin/env bash
# Consolidated deploy script
# Supports:
#  - local (interactive) deployments
#  - ci (non-interactive) deployments (deploys all nixosConfigurations)
#  - create-lxc (create a NixOS LXC on Proxmox remotely or locally)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME=$(basename "$0")

log() { printf "[%s] %s\n" "$(date --iso-8601=seconds 2>/dev/null || date)" "$*" >&2; }
err() { log "ERROR: $*"; }
die() { err "$*"; exit 1; }

trap 'err "Unexpected error at line ${LINENO}"; exit 2' ERR

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH"
}

require_tools() {
  local tools=(nix jq)
  for t in "${tools[@]}"; do check_cmd "$t"; done
}

show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME <command> [options]

Commands:
  local            Interactive deploy (uses fzf) - requires a TTY
  ci               Non-interactive: deploy all nixosConfigurations
  create-lxc       Create an LXC on Proxmox (see options below)
  help             Show this help message

create-lxc options:
  -h, --host       Proxmox host (ssh target). Use 'local' to run locally on the runner.
  -i, --id         Container ID (required)
  -n, --name       Container name (required)
  -p, --ip         Container IP (required)
  -g, --gateway    Gateway (default: 192.168.0.1)
  -m, --mask       Network mask (default: 24)
  --memory         Memory in MB (default: 2024)
  --cores          CPU cores (default: 3)
  -c, --config     Host configuration name from the flake (optional)

Environment:
  RUNNER_LOCAL=true    When set, 'ci' will run locally on the runner (useful for self-hosted runners)
  CREATE_CONTAINERS    When set to 'true', CI will attempt to create containers when missing (requires Proxmox access)

Examples:
  $SCRIPT_NAME local
  $SCRIPT_NAME ci
  $SCRIPT_NAME create-lxc -h proxmox.local -i 101 -n haproxy -p 10.0.0.10 -c haproxy

EOF
}

# Deploy a single configuration using deploy-rs
deploy_config() {
  local cfg="$1"
  log "Deploying configuration: $cfg"

  # Run formatter and quick git commit (non-fatal)
  nix fmt . || log "nix fmt failed or not needed"
  git add . || true
  git commit -m "chore: automatic commit before deployment" || true
  git push || log "git push failed or no remote configured"

  # Run deploy-rs. Non-fatal: capture exit code and continue.
  if ! nix run nixpkgs#deploy-rs -- --remote-build -s .#"$cfg"; then
    err "Deployment failed for $cfg"
    return 1
  fi
  log "Deployment finished for $cfg"
  return 0
}

# Create LXC - either locally (on the runner/proxmox host) or via ssh
create_lxc() {
  local PROXMOX_HOST=""
  local CONTAINER_ID=""
  local CONTAINER_NAME=""
  local CONTAINER_IP=""
  local CONTAINER_GATEWAY="192.168.0.1"
  local CONTAINER_NETMASK="24"
  local CONTAINER_MEMORY="2024"
  local CONTAINER_CORES="3"
  local HOST_CONFIG=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -h|--host) PROXMOX_HOST="$2"; shift 2;;
      -i|--id) CONTAINER_ID="$2"; shift 2;;
      -n|--name) CONTAINER_NAME="$2"; shift 2;;
      -p|--ip) CONTAINER_IP="$2"; shift 2;;
      -g|--gateway) CONTAINER_GATEWAY="$2"; shift 2;;
      -m|--mask) CONTAINER_NETMASK="$2"; shift 2;;
      --memory) CONTAINER_MEMORY="$2"; shift 2;;
      --cores) CONTAINER_CORES="$2"; shift 2;;
      -c|--config) HOST_CONFIG="$2"; shift 2;;
      --help) show_help; return 0;;
      *) die "Unknown option for create-lxc: $1";;
    esac
  done

  for var in PROXMOX_HOST CONTAINER_ID CONTAINER_NAME CONTAINER_IP; do
    if [[ -z "${!var}" ]]; then
      die "Missing required argument --${var,,} for create-lxc"
    fi
  done

  log "Creating NixOS LXC container on Proxmox..."
  log "Host: $PROXMOX_HOST, ID: $CONTAINER_ID, Name: $CONTAINER_NAME, IP: $CONTAINER_IP/$CONTAINER_NETMASK"

  # Prepare remote-local dichotomy
  if [[ "$PROXMOX_HOST" == "local" || "$PROXMOX_HOST" == "localhost" ]]; then
    # Run commands locally
    cmd_prefix=(bash -c)
    remote_exec() { bash -c "$*"; }
    scp_local() { cp "$1" "$2"; }
  else
    # Ensure ssh is available
    check_cmd ssh
    check_cmd scp
    remote_exec() {
      ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$PROXMOX_HOST" "bash -s" <<'REMOTE'
$REMOTE
    }
    scp_local() { scp -o BatchMode=yes -o ConnectTimeout=10 "$1" root@"$PROXMOX_HOST":"$2"; }
  fi

  # Create a temporary configuration.nix to push if provided
  if [[ -n "$HOST_CONFIG" ]]; then
    if [[ -f "./hosts/$HOST_CONFIG/configuration.nix" ]]; then
      TMP_CONF="/tmp/deploy-configuration-$CONTAINER_ID.nix"
      cp "./hosts/$HOST_CONFIG/configuration.nix" "$TMP_CONF"
    else
      log "No specific host configuration file found at ./hosts/$HOST_CONFIG/configuration.nix - skipping push"
      TMP_CONF=""
    fi
  else
    TMP_CONF=""
  fi

  # Build remote script
  read -r -d '' REMOTE_SCRIPT <<'REMOTE_EOF' || true
set -euo pipefail

if ! command -v pveam >/dev/null 2>&1; then
  echo "pveam not found; ensure Proxmox utilities are installed" >&2
  exit 2
fi

# Update templates and find a NixOS template
pveam update || true
TEMPLATE_LINE="$(pveam available | grep -i nixos | sort -V | tail -n1 || true)"
if [[ -z "$TEMPLATE_LINE" ]]; then
  echo "No NixOS template available via pveam" >&2
  exit 3
fi
TEMPLATE_PATH=$(echo "$TEMPLATE_LINE" | awk '{print $2}')
TEMPLATE_NAME=$(echo "$TEMPLATE_LINE" | awk '{print $1}')

# Download template if not present locally
if ! pveam list local | grep -q "$TEMPLATE_NAME"; then
  pveam download local "$TEMPLATE_PATH"
fi

# Prevent creating a container with an existing ID
if pct status $CONTAINER_ID >/dev/null 2>&1; then
  echo "Container ID $CONTAINER_ID already exists" >&2
  exit 4
fi

# Create container
pct create $CONTAINER_ID "$TEMPLATE_NAME" \
  --hostname "$CONTAINER_NAME" \
  --memory $CONTAINER_MEMORY \
  --cores $CONTAINER_CORES \
  --net0 name=eth0,bridge=vmbr0,ip=$CONTAINER_IP/$CONTAINER_NETMASK,gw=$CONTAINER_GATEWAY \
  --storage local-lvm \
  --rootfs local-lvm:8 \
  --ostype nixos \
  --unprivileged 1 \
  --features nesting=1

pct start $CONTAINER_ID
sleep 5

# Prepare configuration inside container if pushed
if [[ -f "/tmp/deploy-configuration-$CONTAINER_ID.nix" ]]; then
  pct push $CONTAINER_ID /tmp/deploy-configuration-$CONTAINER_ID.nix /etc/nixos/configuration.nix
  pct exec $CONTAINER_ID -- sh -c 'source /etc/set-environment || true; nix-channel --update || true; nixos-rebuild switch --upgrade' || true
  rm -f /tmp/deploy-configuration-$CONTAINER_ID.nix || true
fi

echo "Container $CONTAINER_ID created and basic configuration applied"
REMOTE_EOF

  # Inject variables into the remote script using env
  # We will run the remote script with exported variables
  if [[ "$PROXMOX_HOST" == "local" || "$PROXMOX_HOST" == "localhost" ]]; then
    # write the script to a temp file and run it locally with variables
    tmpfile=$(mktemp /tmp/create-lxc.XXXXXX)
    printf '%s\n' "${REMOTE_SCRIPT}" > "$tmpfile"
    export CONTAINER_ID CONTAINER_NAME CONTAINER_IP CONTAINER_GATEWAY CONTAINER_NETMASK CONTAINER_MEMORY CONTAINER_CORES
    bash "$tmpfile"
    rm -f "$tmpfile"
  else
    # push tmp conf if exists
    if [[ -n "$TMP_CONF" ]]; then
      scp_local "$TMP_CONF" "/tmp/deploy-configuration-$CONTAINER_ID.nix"
    fi
    # send and run the script over ssh
    ssh -o BatchMode=yes -o ConnectTimeout=10 root@"$PROXMOX_HOST" bash -s <<REMOTE
export CONTAINER_ID='$CONTAINER_ID'
export CONTAINER_NAME='$CONTAINER_NAME'
export CONTAINER_IP='$CONTAINER_IP'
export CONTAINER_GATEWAY='$CONTAINER_GATEWAY'
export CONTAINER_NETMASK='$CONTAINER_NETMASK'
export CONTAINER_MEMORY='$CONTAINER_MEMORY'
export CONTAINER_CORES='$CONTAINER_CORES'
$(printf '%s\n' "${REMOTE_SCRIPT}")
REMOTE
  fi

  # cleanup
  if [[ -n "$TMP_CONF" && -f "$TMP_CONF" ]]; then
    rm -f "$TMP_CONF" || true
  fi

  log "create-lxc finished"
}

# Interactive local deployment using fzf
cmd_local() {
  check_cmd nix
  check_cmd jq
  check_cmd fzf || die "'fzf' is required for interactive selection"

  log "Collecting NixOS configurations from flake"
  local CONFIGS
  CONFIGS=$(nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames) || die "Failed to evaluate nixosConfigurations"
  local CHOICES
  CHOICES=$(echo "$CONFIGS" | jq -r '.[]')
  if [[ -z "$CHOICES" ]]; then
    die "No nixosConfigurations found in the flake"
  fi
  local SELECTED
  SELECTED=$(echo "$CHOICES" | fzf --prompt "Select config to deploy: ") || true
  if [[ -z "$SELECTED" ]]; then
    log "No configuration selected. Aborting."
    return 0
  fi
  deploy_config "$SELECTED" || die "Deployment failed for $SELECTED"
}

# Non-interactive CI deploy: deploy all nixosConfigurations
cmd_ci() {
  require_tools

  log "Running CI deploy: discovering nixosConfigurations..."
  local CONFIGS_JSON
  CONFIGS_JSON=$(nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames) || die "Failed to evaluate nixosConfigurations"
  local CONFIGS
  CONFIGS=$(echo "$CONFIGS_JSON" | jq -r '.[]')

  if [[ -z "$CONFIGS" ]]; then
    log "No nixosConfigurations to deploy. Exiting."
    return 0
  fi

  local failures=()
  for cfg in $CONFIGS; do
    if ! deploy_config "$cfg"; then
      failures+=("$cfg")
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    err "Deployments failed for: ${failures[*]}"
    return 3
  fi

  log "CI deploy finished successfully for all configurations"
}

# Entrypoint
main() {
  if [[ $# -lt 1 ]]; then show_help; exit 0; fi
  cmd="$1"; shift
  case $cmd in
    help|-h|--help) show_help;;
    local) cmd_local ;;
    ci) cmd_ci ;;
    create-lxc) create_lxc "$@" ;;
    *) die "Unknown command: $cmd" ;;
  esac
}

main "$@"
