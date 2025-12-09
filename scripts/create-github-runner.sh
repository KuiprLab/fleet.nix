#!/usr/bin/env bash
# Script to create a GitHub Actions self-hosted runner inside a Proxmox LXC
# Usage: ./scripts/create-github-runner.sh --proxmox-host PROXMOX --id 120 --name runner01 --ip 10.0.0.20 --github-url https://github.com/owner/repo --token REGISTRATION_TOKEN [options]

set -euo pipefail
IFS=$'\n\t'

log() { printf "[%s] %s\n" "$(date --iso-8601=seconds 2>/dev/null || date)" "$*" >&2; }
err() { log "ERROR: $*"; }
die() {
	err "$*"
	exit 1
}

check_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }

show_help() {
	cat <<EOF
Usage: $0 [options]

Options:
  --proxmox-host HOST     Proxmox host where LXC should be created or 'local'
  --id ID                 Container ID (required)
  --name NAME             Container name (required)
  --ip IP                 Container IP address (required)
  --github-url URL        GitHub repository or organization URL (eg: https://github.com/owner/repo or https://github.com/org) (required)
  --token TOKEN           Runner registration token (required)
  --labels LABELS         Comma-separated labels for the runner (default: self-hosted,proxmox)
  --skip-create           Skip creating the LXC; assume the target container already exists and is reachable at --ip
  --ssh-user USER         SSH user to use when connecting to the created container (default: root)
  --timeout SECONDS       SSH connection timeout waiting for the container (default: 300)
  --help                  Show this help

Notes:
  - The script will attempt to create a container by calling the consolidated deploy script: ./scripts/deploy.sh create-lxc ...
  - You must provide a GitHub runner registration token (see README.md for how to create one).
  - The created runner will attempt to run the official actions runner and install the service.

EOF
}

# defaults
PROXMOX_HOST=""
CONTAINER_ID=""
CONTAINER_NAME=""
CONTAINER_IP=""
GITHUB_URL=""
TOKEN=""
LABELS="self-hosted,proxmox"
SKIP_CREATE=false
SSH_USER="root"
TIMEOUT=300

while [[ $# -gt 0 ]]; do
	case "$1" in
	--proxmox-host)
		PROXMOX_HOST="$2"
		shift 2
		;;
	--id)
		CONTAINER_ID="$2"
		shift 2
		;;
	--name)
		CONTAINER_NAME="$2"
		shift 2
		;;
	--ip)
		CONTAINER_IP="$2"
		shift 2
		;;
	--github-url)
		GITHUB_URL="$2"
		shift 2
		;;
	--token)
		TOKEN="$2"
		shift 2
		;;
	--labels)
		LABELS="$2"
		shift 2
		;;
	--skip-create)
		SKIP_CREATE=true
		shift 1
		;;
	--ssh-user)
		SSH_USER="$2"
		shift 2
		;;
	--timeout)
		TIMEOUT="$2"
		shift 2
		;;
	--help)
		show_help
		exit 0
		;;
	*) die "Unknown argument: $1" ;;
	esac
done

for v in CONTAINER_ID CONTAINER_NAME CONTAINER_IP GITHUB_URL TOKEN; do
	if [[ -z "${!v}" ]]; then
		die "Missing required argument --${v,,}. Run with --help for usage."
	fi
done

check_cmd ssh
check_cmd scp
check_cmd curl

# Optionally create the container using the consolidated deploy script
if [[ "$SKIP_CREATE" == "false" ]]; then
	if [[ ! -x ./scripts/deploy.sh ]]; then
		die "Consolidated deploy script './scripts/deploy.sh' not found or not executable"
	fi
	log "Creating container using ./scripts/deploy.sh create-lxc"
	./scripts/deploy.sh create-lxc -h "$PROXMOX_HOST" -i "$CONTAINER_ID" -n "$CONTAINER_NAME" -p "$CONTAINER_IP" -c "$CONTAINER_NAME" || log "create-lxc returned non-zero; continuing"
fi

# Wait for SSH to become available on the container
log "Waiting for SSH on $CONTAINER_IP (timeout ${TIMEOUT}s)"
start_ts=$(date +%s)
while true; do
	if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER"@"$CONTAINER_IP" 'echo ok' >/dev/null 2>&1; then
		log "SSH reachable on $CONTAINER_IP"
		break
	fi
	now=$(date +%s)
	if ((now - start_ts > TIMEOUT)); then
		die "Timed out waiting for SSH on $CONTAINER_IP"
	fi
	sleep 5
done

# Build the remote runner setup script
read -r -d '' REMOTE_SETUP <<'REMOTE' || true
#!/usr/bin/env bash
set -euo pipefail

GITHUB_URL="__GITHUB_URL__"
TOKEN="__TOKEN__"
LABELS="__LABELS__"
RUNNER_USER="__RUNNER_USER__"

log(){ printf "[%s] %s\n" "$(date --iso-8601=seconds 2>/dev/null || date)" "$*" >&2; }
err(){ log "ERROR: $*"; }

# create runner user
if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
  log "Creating user $RUNNER_USER"
  useradd --create-home --shell /bin/bash "$RUNNER_USER" || true
fi

# ensure /home/$RUNNER_USER exists
mkdir -p /home/$RUNNER_USER
chown $RUNNER_USER:$RUNNER_USER /home/$RUNNER_USER

cd /home/$RUNNER_USER
RUNNER_DIR="actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# detect latest runner release and download linux-x64 asset
log "Querying latest runner release from GitHub"
RELEASE_JSON=$(curl -sS https://api.github.com/repos/actions/runner/releases/latest)
ASSET_URL=$(echo "$RELEASE_JSON" | grep 'browser_download_url' | grep 'linux-x64' | head -n1 | cut -d '"' -f4)
if [[ -z "$ASSET_URL" ]]; then
  err "Could not detect runner download URL"
  exit 2
fi

log "Downloading $ASSET_URL"
curl -sS -L "$ASSET_URL" -o actions-runner.tar.gz

log "Extracting"
tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz

# give ownership
chown -R $RUNNER_USER:$RUNNER_USER /home/$RUNNER_USER

# configure the runner (replace if exists)
log "Configuring runner for $GITHUB_URL"
./config.sh --unattended --url "$GITHUB_URL" --token "$TOKEN" --labels "$LABELS" --work _work --replace

# install and start the service
log "Installing runner service"
./svc.sh install
./svc.sh start || true

log "Runner setup finished"
REMOTE

# Inject variables safely
REMOTE_SETUP=${REMOTE_SETUP//"__GITHUB_URL__"/"$GITHUB_URL"}
REMOTE_SETUP=${REMOTE_SETUP//"__TOKEN__"/"$TOKEN"}
REMOTE_SETUP=${REMOTE_SETUP//"__LABELS__"/"$LABELS"}
REMOTE_SETUP=${REMOTE_SETUP//"__RUNNER_USER__"/"actions"}

# copy and run remote setup script
tmpfile=$(mktemp /tmp/setup-runner.XXXXXX)
printf '%s\n' "$REMOTE_SETUP" >"$tmpfile"
scp -o BatchMode=yes -o StrictHostKeyChecking=no "$tmpfile" "$SSH_USER"@"$CONTAINER_IP":/tmp/setup-runner.sh
rm -f "$tmpfile"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$SSH_USER"@"$CONTAINER_IP" 'bash /tmp/setup-runner.sh'

log "Runner installation completed on $CONTAINER_IP"

echo "Runner should now be registered for $GITHUB_URL with labels: $LABELS"
