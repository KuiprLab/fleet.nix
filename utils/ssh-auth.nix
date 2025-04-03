# utils/ssh-auth.nix
{ config, lib, pkgs, ... }:

let
  # Function to generate SSH key and store in 1Password
  generateAndStoreSSHKey = hostname: ''
    # Check if 1Password CLI is available
    if ! command -v op &> /dev/null; then
      echo "1Password CLI not found. Please install it first."
      exit 1
    fi
    
    # Check if we're authenticated with 1Password
    if ! op account get &> /dev/null; then
      echo "Not authenticated with 1Password. Please run 'eval $(op signin)' first."
      exit 1
    fi
    
    # Check if an entry for this host already exists in 1Password
    if op item get "nixos-deploy-${hostname}" &> /dev/null; then
      echo "SSH key for ${hostname} already exists in 1Password."
      
      # Retrieve the private key and save it locally
      mkdir -p ~/.ssh/nixos-deploy
      op item get "nixos-deploy-${hostname}" --field "private_key" > ~/.ssh/nixos-deploy/${hostname}
      chmod 600 ~/.ssh/nixos-deploy/${hostname}
      
      # Get the public key for display
      PUBKEY=$(op item get "nixos-deploy-${hostname}" --field "public_key")
      echo "Retrieved SSH key for ${hostname} from 1Password:"
      echo "$PUBKEY"
    else
      echo "Generating new SSH key pair for ${hostname}..."
      
      # Create directory for deploy keys
      mkdir -p ~/.ssh/nixos-deploy
      
      # Generate new SSH key
      ssh-keygen -t ed25519 -N "" -C "nixos-deploy-${hostname}" -f ~/.ssh/nixos-deploy/${hostname}
      
      # Store the keys in 1Password
      PRIVKEY=$(cat ~/.ssh/nixos-deploy/${hostname})
      PUBKEY=$(cat ~/.ssh/nixos-deploy/${hostname}.pub)
      
      op item create --category="Secure Note" \
        --title="nixos-deploy-${hostname}" \
        --vault="NixOS" \
        "private_key=$PRIVKEY" \
        "public_key=$PUBKEY" \
        "hostname=${hostname}" \
        "created_date=$(date -Iseconds)"
      
      echo "Created and stored new SSH key for ${hostname} in 1Password."
      echo "Public key:"
      echo "$PUBKEY"
      
      echo ""
      echo "You need to add this public key to the target system before deployment."
      echo "You can do this manually or use the setup script:"
      echo "  ./setup-host.sh ${hostname} \"$PUBKEY\""
    fi
    
    # Configure SSH to use this key for the host
    if ! grep -q "Host ${hostname}" ~/.ssh/config; then
      echo -e "\nHost ${hostname}\n  IdentityFile ~/.ssh/nixos-deploy/${hostname}\n  User root\n" >> ~/.ssh/config
      echo "Added host configuration to ~/.ssh/config"
    fi
  '';
  
  # Script to setup a new host with the SSH key
  setupHostScript = pkgs.writeScriptBin "setup-host.sh" ''
    #!/usr/bin/env bash
    set -e
    
    if [ $# -lt 2 ]; then
      echo "Usage: $0 <hostname> <pubkey>"
      echo "  or   $0 <hostname> --from-1password"
      exit 1
    fi
    
    HOSTNAME=$1
    
    if [ "$2" == "--from-1password" ]; then
      if ! command -v op &> /dev/null; then
        echo "1Password CLI not found. Please install it first."
        exit 1
      fi
      
      if ! op item get "nixos-deploy-$HOSTNAME" &> /dev/null; then
        echo "No SSH key found in 1Password for $HOSTNAME."
        exit 1
      fi
      
      PUBKEY=$(op item get "nixos-deploy-$HOSTNAME" --field "public_key")
    else
      PUBKEY=$2
    fi
    
    echo "Setting up SSH access for $HOSTNAME with public key:"
    echo "$PUBKEY"
    
    # Get IP from flake.nix
    IP=$(grep -A 10 "$HOSTNAME = {" flake.nix | grep "hostname" | head -1 | cut -d'"' -f2)
    
    if [ -z "$IP" ]; then
      echo "Could not determine IP address from flake.nix. Please enter it manually:"
      read -p "IP address: " IP
    fi
    
    echo "Using IP address: $IP"
    
    # Check if we can connect with root password
    if ssh -o "StrictHostKeyChecking=no" root@$IP "echo 'Connected successfully'" 2>/dev/null; then
      echo "Successfully connected with password. Adding SSH key..."
      
      # Create authorized_keys file if it doesn't exist
      ssh root@$IP "mkdir -p /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
      
      # Add the key
      echo "$PUBKEY" | ssh root@$IP "cat >> /root/.ssh/authorized_keys"
      
      echo "SSH key added successfully!"
      
      # Suggest disabling password authentication
      echo "You can now deploy with SSH key authentication."
      echo "Remember to update your NixOS configuration to disable password authentication."
    else
      echo "Could not connect with password. You may need to manually add the SSH key to the host."
      echo "Run this command on the target system:"
      echo "mkdir -p /root/.ssh && echo '$PUBKEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
    fi
  '';

in {
  # Make the setup script available in the environment
  environment.systemPackages = [ setupHostScript ];
  
  # This function should be used in your deploy script
  # before trying to deploy to a host
  ensureSSHKey = generateAndStoreSSHKey;
}
