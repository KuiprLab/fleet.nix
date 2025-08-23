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


# Test if all configurations build successfully
test:
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🧪 Testing all NixOS configurations..."
    
    # Get all configuration names
    configs=($(nix --extra-experimental-features flakes --extra-experimental-features nix-command flake show --json 2>/dev/null | jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "hl-lxc-nginx hl-lxc-bind hl-lxc-unifi hl-lxc-homebridge hl-lxc-musicassistant"))
    
    failed=()
    passed=()
    
    for config in "${configs[@]}"; do
        echo "  🔨 Building $config..."
        if nix --extra-experimental-features flakes --extra-experimental-features nix-command build ".#nixosConfigurations.$config.config.system.build.toplevel" --no-link --show-trace 2>/dev/null; then
            echo "    ✅ $config builds successfully"
            passed+=("$config")
        else
            echo "    ❌ $config failed to build"
            failed+=("$config")
        fi
    done
    
    echo ""
    echo "📊 Test Results:"
    echo "=================="
    echo "✅ Passed: ${#passed[@]} configurations"
    for config in "${passed[@]}"; do
        echo "   - $config"
    done
    
    if [ ${#failed[@]} -gt 0 ]; then
        echo "❌ Failed: ${#failed[@]} configurations"
        for config in "${failed[@]}"; do
            echo "   - $config"
        done
        exit 1
    else
        echo "🎉 All configurations build successfully!"
    fi


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
