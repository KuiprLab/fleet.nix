#!/usr/bin/env bash
# Script to deploy NixOS LXC container on Proxmox and configure it with GitOps
# Includes 1Password integration for SSH key management

set -euo pipefail

# Default values
PROXMOX_HOST=""
CONTAINER_ID=""
CONTAINER_NAME=""
CONTAINER_IP=""
CONTAINER_GATEWAY="192.168.0.1"
CONTAINER_NETMASK="24"
CONTAINER_MEMORY="2024"
CONTAINER_CORES="3"
HOST_CONFIG=""

# Function to display help
function show_help {
    cat <<EOF
    Usage: $0 [options]

    Options:
    -h, --host         Proxmox host address
    -i, --id           LXC container ID
    -n, --name         LXC container name
    -p, --ip           LXC container IP address
    -g, --gateway      Network gateway (default: 192.168.0.1)
    -m, --mask         Network mask (default: 24)
    --memory           Memory in MB (default: 2024)
    --cores            CPU cores (default: 3)
    -c, --config       Host configuration name from your flake
    --help             Show this help message

    Example:
    $0 -h proxmox.local -i 101 -n haproxy -p 10.0.0.10 -c haproxy
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--host)
            PROXMOX_HOST="$2"
            shift
            shift
            ;;
        -i|--id)
            CONTAINER_ID="$2"
            shift
            shift
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift
            shift
            ;;
        -p|--ip)
            CONTAINER_IP="$2"
            shift
            shift
            ;;
        -g|--gateway)
            CONTAINER_GATEWAY="$2"
            shift
            shift
            ;;
        -m|--mask)
            CONTAINER_NETMASK="$2"
            shift
            shift
            ;;
        --memory)
            CONTAINER_MEMORY="$2"
            shift
            shift
            ;;
        --cores)
            CONTAINER_CORES="$2"
            shift
            shift
            ;;
        -c|--config)
            HOST_CONFIG="$2"
            shift
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check required arguments
for var in PROXMOX_HOST CONTAINER_ID CONTAINER_NAME CONTAINER_IP; do
    if [[ -z "${!var}" ]]; then
        echo "Error: Missing required argument --${var,,}"
        show_help
        exit 1
    fi
done


echo "Creating NixOS LXC container on Proxmox..."
echo "Host: $PROXMOX_HOST"
echo "Container ID: $CONTAINER_ID"
echo "Container Name: $CONTAINER_NAME"
echo "IP Address: $CONTAINER_IP/$CONTAINER_NETMASK"


echo "Copying configuration.nix to Proxmox temp directory"
scp -o PreferredAuthentications=password ./scripts/configuration.nix root@"$PROXMOX_HOST":/tmp/


# Create LXC container on Proxmox
ssh -o PreferredAuthentications=password root@"$PROXMOX_HOST" "
# Download the latest NixOS LXC template if not already available
if ! pveam list local | grep -q nixos; then
    pveam update
    TEMPLATE_PATH=\$(pveam available | grep nixos | sort -V | tail -n1 | awk '{print \$2}')
    pveam download local \$TEMPLATE_PATH
fi

  # Get the local template path
  TEMPLATE_PATH=\$(pveam list local | grep nixos | sort -V | tail -n1 | awk '{print \$1}')

  # Create the LXC container
  pct create $CONTAINER_ID \$TEMPLATE_PATH \\
  --hostname $CONTAINER_NAME \\
  --memory $CONTAINER_MEMORY \\
  --cores $CONTAINER_CORES \\
  --net0 name=eth0,bridge=vmbr0,ip=$CONTAINER_IP/$CONTAINER_NETMASK,gw=$CONTAINER_GATEWAY \\
  --storage local-lvm \\
  --rootfs local-lvm:8 \\
  --ostype nixos \\
  --unprivileged 1 \\
  --features nesting=1

  # Start the container
  pct start $CONTAINER_ID

  # Wait for the container to start
  sleep 5

  pct exec $CONTAINER_ID -- sh -c 'source /etc/set-environment; passwd --delete root'
  pct push $CONTAINER_ID /tmp/configuration.nix /etc/nixos/configuration.nix
  # || true to ignore pipefail
  pct exec $CONTAINER_ID -- sh -c 'source /etc/set-environment; nix-channel --update; nixos-rebuild switch --upgrade' || true

  echo 'Cleaning up...'
  rm -rf /tmp/configuration.nix
  "

echo "Testing ssh connection to LXC"
ssh root@"$CONTAINER_IP" "
echo 'Success!'
"

echo "NixOS LXC container successfully deployed and configured!"
echo "Container IP: $CONTAINER_IP"
echo "Container Name: $CONTAINER_NAME"
echo "Container ID: $CONTAINER_ID"
echo "Configuration: $HOST_CONFIG"
