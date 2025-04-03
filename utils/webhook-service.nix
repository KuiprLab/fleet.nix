{ config, pkgs, lib, ... }:

let
  port = 9000;
  webhookScript = pkgs.writeScriptBin "github-webhook-handler" ''
    #!/bin/sh
    set -e

    # Log file for debugging
    LOG_FILE="/var/log/github-webhook.log"
    
    echo "[$(date)] Webhook triggered" >> $LOG_FILE
    
    # Pull the latest changes from the repository
    cd /etc/nixos
    ${pkgs.git}/bin/git pull origin main >> $LOG_FILE 2>&1
    
    # Apply the new configuration
    echo "[$(date)] Running nixos-rebuild switch..." >> $LOG_FILE
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#$(hostname) >> $LOG_FILE 2>&1
    
    echo "[$(date)] Deployment completed successfully" >> $LOG_FILE
  '';
in {
  # Install webhook and other requirements
  environment.systemPackages = with pkgs; [
    webhook
    webhookScript
    git
  ];

  # Set up the webhook service
  systemd.services.github-webhook = {
    description = "GitHub Webhook Handler for NixOS config";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = ''
        ${pkgs.webhook}/bin/webhook \
          -hooks /etc/webhook/hooks.json \
          -verbose \
          -port ${toString port}
      '';
      Restart = "always";
      RestartSec = "10";
    };
  };

  # Create the webhook hooks configuration
  system.activationScripts.webhookConfig = ''
    mkdir -p /etc/webhook
    cat > /etc/webhook/hooks.json << 'EOF'
    [
      {
        "id": "nixos-update",
        "execute-command": "${webhookScript}/bin/github-webhook-handler",
        "command-working-directory": "/etc/nixos",
        "trigger-rule": {
          "match": {
            "type": "payload-hash-sha1",
            "secret": "dVtiyigPwn9479goLmix",
            "parameter": {
              "source": "header",
              "name": "X-Hub-Signature"
            }
          }
        }
      }
    ]
    EOF
    chmod 600 /etc/webhook/hooks.json
  '';

  # Open the webhook port
  networking.firewall.allowedTCPPorts = [ port ];

  # Create log file
  system.activationScripts.createWebhookLogFile = ''
    touch /var/log/github-webhook.log
    chmod 644 /var/log/github-webhook.log
  '';
}
