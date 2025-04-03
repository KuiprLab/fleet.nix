#!/usr/bin/env bash

set -e

# Check if 1Password CLI is installed
if ! command -v op &> /dev/null; then
  echo "1Password CLI not found. Please install it first."
  echo "Visit https://1password.com/downloads/command-line/ for installation instructions."
  exit 1
fi

CONFIGS=$(nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')
HOST=$(echo "$CONFIGS" | fzf --prompt "Select config to deploy: ")


ensure_ssh_key(){
    if op item get "$HOST"  &> /dev/null; then
        echo "SSH key for ${HOST} already exists in 1Password."
    else
      echo "Generating new SSH key pair for ${HOST}..."
      
      op item create --category ssh --title "${HOST}" --ssh-generate-key RSA,2048 --tags "Homelab" "ssh"

      PUBLIC_KEY=$(op read "op://Personal/${HOST}/public key")
      
      echo "Created and stored new SSH key for ${HOST} in 1Password."
      echo "$PUBLIC_KEY" >> ./utils/authorizedKeys
    fi
}


# Deploy using deploy-rs
ensure_ssh_key
echo "Deploying $HOST..."
deploy_config() {
  if [ -n "$HOST" ]; then
    echo "Deploying configuration: $HOST"
    nix run nixpkgs#deploy-rs -- --remote-build -s .#"$HOST"
  else
    echo "No configuration selected."
  fi
}

deploy_config
echo "Deployment complete!"

