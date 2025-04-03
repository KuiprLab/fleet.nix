#!/usr/bin/env bash
# Script to deploy NixOS LXC container on Proxmox and configure it with GitOps

set -euo pipefail

# Default values
PROXMOX_HOST=""
CONTAINER_ID=""
CONTAINER_NAME=""
CONTAINER_IP=""
CONTAINER_GATEWAY="10.0.0.1"
CONTAINER_NETMASK="24"
CONTAINER_MEMORY="1024"
CONTAINER_CORES="1"
SSH_KEY=""
GIT_REPO="https://github.com/KuiprLab/fleet.nix.git"
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
    -g, --gateway      Network gateway (default: 10.0.0.1)
    -m, --mask         Network mask (default: 24)
    --memory           Memory in MB (default: 1024)
    --cores            CPU cores (default: 1)
    -k, --ssh-key      Path to SSH public key
    -r, --git-repo     Git repository URL (default: github:yourusername/nixos-homelab)
    -c, --config       Host configuration name from your flake
    --help             Show this help message

    Example:
    $0 -h proxmox.local -i 101 -n haproxy -p 10.0.0.10 -c haproxy -k ~/.ssh/id_ed25519.pub
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
        -k|--ssh-key)
            SSH_KEY="$2"
            shift
            shift
            ;;
        -r|--git-repo)
            GIT_REPO="$2"
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
for var in PROXMOX_HOST CONTAINER_ID CONTAINER_NAME CONTAINER_IP SSH_KEY HOST_CONFIG; do
    if [[ -z "${!var}" ]]; then
        echo "Error: Missing required argument --${var,,}"
        show_help
        exit 1
    fi
done

# Read SSH key
if [[ ! -f "$SSH_KEY" ]]; then
    echo "Error: SSH key file not found: $SSH_KEY"
    exit 1
fi
SSH_KEY_CONTENT=$(cat "$SSH_KEY")

echo "Creating NixOS LXC container on Proxmox..."
echo "Host: $PROXMOX_HOST"
echo "Container ID: $CONTAINER_ID"
echo "Container Name: $CONTAINER_NAME"
echo "IP Address: $CONTAINER_IP/$CONTAINER_NETMASK"

# Create LXC container on Proxmox
ssh root@$PROXMOX_HOST "
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
  sleep 10
  "

  echo "NixOS LXC container created successfully!"

  echo "Setting up SSH access and NixOS configuration..."
  # Generate a temporary SSH key for initial configuration
  TMP_KEY=$(mktemp)
  TMP_KEY_PUB="${TMP_KEY}.pub"
  ssh-keygen -t ed25519 -f "$TMP_KEY" -N "" -q

# Copy the temporary public key to the container
ssh root@$PROXMOX_HOST "
# Check if the container is running
if ! pct status $CONTAINER_ID | grep -q running; then
    pct start $CONTAINER_ID
    sleep 10
fi

  # Add the temporary SSH key to the container
  pct exec $CONTAINER_ID -- mkdir -p /root/.ssh
  pct exec $CONTAINER_ID -- chmod 700 /root/.ssh
  pct push $CONTAINER_ID $TMP_KEY_PUB /root/.ssh/authorized_keys
  pct exec $CONTAINER_ID -- chmod 600 /root/.ssh/authorized_keys
  "

# Get the container's IP for direct SSH access
CONTAINER_SSH_IP=$(ssh root@$PROXMOX_HOST "pct config $CONTAINER_ID | grep -oP 'ip=\K[^/]+'")

# Set up the NixOS configuration
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $TMP_KEY"

# Install Git and clone the repository
ssh $SSH_OPTIONS root@$CONTAINER_SSH_IP "
# Install git if not already installed
if ! command -v git &> /dev/null; then
    nix-env -iA nixos.git
fi

  # Create NixOS configuration directory
  mkdir -p /etc/nixos

  # Clone the repository
  git clone $GIT_REPO /etc/nixos
  cd /etc/nixos

  # Create basic configuration if not already present
  if [ ! -f /etc/nixos/configuration.nix ]; then
      cat > /etc/nixos/configuration.nix <<EOF
      { config, pkgs, ... }:

          {
              imports = [ ./hosts/$HOST_CONFIG/configuration.nix ];
          }
EOF
  fi

  # Add the SSH key for future access
  mkdir -p /etc/nixos/secrets
  echo '$SSH_KEY_CONTENT' > /etc/nixos/secrets/ssh_authorized_key.pub

  # Apply the configuration
  nixos-rebuild switch --flake .#$HOST_CONFIG

  # Set up automatic updates
  systemctl enable flake-update.timer
  systemctl start flake-update.timer
  "

  echo "Cleaning up..."
  rm -f "$TMP_KEY" "$TMP_KEY_PUB"

  echo "NixOS LXC container successfully deployed and configured!"
  echo "Container IP: $CONTAINER_SSH_IP"
  echo "Container Name: $CONTAINER_NAME"
  echo "Container ID: $CONTAINER_ID"
  echo "Configuration: $HOST_CONFIG"
  echo
  echo "You can now SSH into the container using your SSH key:"
  echo "ssh admin@$CONTAINER_SSH_IP"
