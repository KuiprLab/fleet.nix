{
  config,
  pkgs,
  lib,
  self ? null,
  ...
}: {
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
      ${pkgs.git}/bin/git clone https://github.com/KuiprLab/fleet.nix /etc/nixos

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
        set -e
        LOG_FILE="/var/log/nixos-update.log"
        echo "[$(date)] Checking for updates..." >> $LOG_FILE

        cd /etc/nixos
        ${pkgs.git}/bin/git fetch origin

        LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
        REMOTE=$(${pkgs.git}/bin/git rev-parse origin/main)

        if [ "$LOCAL" != "$REMOTE" ]; then
          echo "[$(date)] Updates detected, pulling changes..." >> $LOG_FILE
          ${pkgs.git}/bin/git pull origin main

          # Look for deploy tags that are newer than our current commit
          LATEST_TAG=$(${pkgs.git}/bin/git tag -l "deploy-*" --sort=-committerdate | head -n 1)

          if [ ! -z "$LATEST_TAG" ]; then
            echo "[$(date)] Found deployment tag: $LATEST_TAG" >> $LOG_FILE

            # Check if this tag is for a commit we don't have yet
            TAG_COMMIT=$(${pkgs.git}/bin/git rev-list -n 1 $LATEST_TAG)

            if [ "$TAG_COMMIT" != "$LOCAL" ]; then
              echo "[$(date)] Applying validated configuration from tag $LATEST_TAG" >> $LOG_FILE
              ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#$(hostname) 2>&1 | tee -a $LOG_FILE

              # Notify of successful update
              echo "[$(date)] System updated successfully to $LATEST_TAG" >> $LOG_FILE
              ${pkgs.libnotify}/bin/notify-send "NixOS Update" "System updated to $LATEST_TAG" || true
            else
              echo "[$(date)] Already at latest tagged version" >> $LOG_FILE
            fi
          else
            echo "[$(date)] No deployment tags found" >> $LOG_FILE
          fi
        else
          echo "[$(date)] No updates found." >> $LOG_FILE
        fi
      '';
      TimeoutSec = "300";
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  systemd.timers.check-nixos-updates = {
    wantedBy = ["timers.target"];
    partOf = ["check-nixos-updates.service"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min"; # Check more frequently (every 15 minutes)
      RandomizedDelaySec = "2min";
    };
  };

  # Add a manual trigger option
  systemd.services.force-nixos-update = {
    description = "Force NixOS configuration update";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "force-nixos-update" ''
        systemctl start check-nixos-updates.service
        journalctl -fu check-nixos-updates.service
      '';
    };
  };

  # Create log file
  system.activationScripts.createUpdateLogFile = ''
    touch /var/log/nixos-update.log
    chmod 644 /var/log/nixos-update.log
  '';

  # Link current system to flake input if provided
  nix.registry = lib.mkIf (self != null) {
    current.flake = self;
  };
}
