#!/usr/bin/env bash
set -euo pipefail

# Prompt for necessary values
read -p "Enter Proxmox host (e.g. proxmox.example.com): " PROXMOX_HOST
read -p "Enter SSH user for Proxmox host [root]: " SSH_USER
SSH_USER=${SSH_USER:-root}
read -p "Enter container ID: " CTID

# Define additional variables
CONFIG_PATH="/etc/nixos/configuration.nix"
LOCAL_CONFIG_FILE="./scripts/configuration.nix"

# Ensure the configuration file exists
if [ ! -f "$LOCAL_CONFIG_FILE" ]; then
  echo "Configuration file '$LOCAL_CONFIG_FILE' not found!"
  exit 1
fi

# Read the local NixOS configuration file into a variable
LOCAL_CONFIG_CONTENT=$(cat "$LOCAL_CONFIG_FILE")

# Build the remote script
REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail

# Define variables on the remote side
CTID="${CTID}"
CONFIG_PATH="${CONFIG_PATH}"

echo "Removing root password inside the container..."
# Use the full path to passwd in NixOS
pct exec "\$CTID" -- /run/current-system/sw/bin/passwd --delete root

echo "Writing minimal NixOS configuration to \$CONFIG_PATH..."
pct exec "\$CTID" -- /run/current-system/sw/bin/bash -c 'cat > "\$CONFIG_PATH"' <<'CONFIG_EOF'
${LOCAL_CONFIG_CONTENT}
CONFIG_EOF

echo "Updating Nix channels inside container..."
pct exec "\$CTID" -- nix-channel --update

echo "Switching NixOS configuration (this may take a while)..."
pct exec "\$CTID" -- nixos-rebuild switch --upgrade

echo "Retrieving container IP address..."
IP_ADDR=\$(pct exec "\$CTID" -- /run/current-system/sw/bin/ip a)
echo "Container IP address: \$IP_ADDR"
EOF
)

# Send the remote script via standard input to SSH
echo "Starting remote NixOS container setup on ${PROXMOX_HOST}..."
ssh "${SSH_USER}@${PROXMOX_HOST}" bash <<< "$REMOTE_SCRIPT"
