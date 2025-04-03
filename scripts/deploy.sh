#!/bin/bash

deploy_config() {
  # List available configuration names as JSON, parse them with jq.
  local configs
  configs=$(nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')
  # Use fzf to select one.
  local chosen
  chosen=$(echo "$configs" | fzf --prompt "Select config to deploy: ")
  if [ -n "$chosen" ]; then
    echo "Deploying configuration: $chosen"
    nix run nixpkgs#deploy-rs -- --remote-build -s .#"$chosen"
  else
    echo "No configuration selected."
  fi
}

deploy_config
