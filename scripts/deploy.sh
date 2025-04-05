#!/usr/bin/env bash

set -e


CONFIGS=$(nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')
HOST=$(echo "$CONFIGS" | fzf --prompt "Select config to deploy: ")

# Deploy using deploy-rs
echo "Deploying $HOST..."
if [ -n "$HOST" ]; then
  echo "Deploying configuration: $HOST"
  nix fmt .
  git add . || true
  git commit -m "chore: automatic commit before deployment" || true
  git push || true
  nix run nixpkgs#deploy-rs -- --remote-build -s .#"$HOST"
else
  echo "No configuration selected."
fi
echo "Deployment complete!"

