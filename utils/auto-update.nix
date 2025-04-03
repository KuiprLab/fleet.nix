{ config, pkgs, lib, self ? null, ... }:

{
  # Configure automatic Git repository setup
  system.activationScripts.setupGitRepo = ''
    # Check if /etc/nixos is already a git repository
    if [ ! -d /etc/nixos/.git ]; then
      echo "Setting up Git repository in /etc/nixos"
      
      # Back up any existing configuration
      if [ -d /etc/nixos ]; then
        mv /etc/nixos /etc/nixos.bak
      fi
      
      # Clone the repository
      ${pkgs.git}/bin/git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git /etc/nixos
      
      # Set Git configuration to allow pulling without authentication for public repos
      cd /etc/nixos
      ${pkgs.git}/bin/git config pull.rebase false
      ${pkgs.git}/bin/git config --local user.email "auto-updater@$(hostname).local"
      ${pkgs.git}/bin/git config --local user.name "NixOS Auto Updater"
    fi
  '';

  # Scheduled checks for updates
  systemd.services.check-nixos-updates = {
    description = "Check for NixOS configuration updates";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "check-nixos-updates" ''
        cd /etc/nixos
        ${pkgs.git}/bin/git fetch origin
        
        LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
        REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main)
        
        if [ "$LOCAL" != "$REMOTE" ]; then
          echo "Updates detected, pulling changes..."
          ${pkgs.git}/bin/git pull origin main
          ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#$(hostname)
        else
          echo "No updates found."
        fi
      '';
    };
  };

  systemd.timers.check-nixos-updates = {
    wantedBy = [ "timers.target" ];
    partOf = [ "check-nixos-updates.service" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      RandomizedDelaySec = "5min";
    };
  };

  # Link current system to flake input if provided
  nix.registry = lib.mkIf (self != null) {
    current.flake = self;
  };
}
