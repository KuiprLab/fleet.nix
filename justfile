alias d := deploy
alias u := update
alias c := clean

default:
    just --list


deploy:
    @git pull
    @nixos-rebuild switch --flake .


update:
    @git pull
    nix --extra-experimental-features flakes --extra-experimental-features nix-command flake update


# Manual cleanup trigger (uses native NixOS tools)
clean:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🧹 Running manual cleanup using NixOS native tools..."

    # Trigger immediate garbage collection
    sudo nix-collect-garbage --delete-older-than 1d

    # Optimize store
    sudo nix-store --optimise

    # Clean user profiles
    nix-collect-garbage --delete-older-than 1d

    # Clean journal if systemd is available
    if command -v journalctl &> /dev/null; then
        sudo journalctl --vacuum-time=7d --vacuum-size=100M
    fi

    echo "✅ Manual cleanup completed!"
