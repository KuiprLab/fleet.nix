{ pkgs, lib, common, ... }:

{
  imports = [
    # You can import hardware-specific configurations here
  ];

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (common.mkLxcConfig {
      hostname = "technitium";
      ipAddress = "10.0.0.11";  # Update with your actual IP
    })
    {
      # Technitium DNS Server configuration
      virtualisation.docker = {
        enable = true;
        autoPrune.enable = true;
      };
      
      # Create systemd service for Technitium DNS server
      virtualisation.oci-containers.containers = {
        technitium = {
          image = "technitium/dns-server:latest";
          ports = [
            "53:53/udp"  # DNS
            "53:53/tcp"  # DNS over TCP
            "80:80"      # Web console (HTTP)
            "443:443"    # Web console (HTTPS)
            "8953:8953"  # DNS over TLS
          ];
          volumes = [
            "/var/lib/technitium:/etc/dns"
          ];
          environment = {
            TZ = "UTC";
          };
          extraOptions = [
            "--restart=unless-stopped"
          ];
        };
      };
      
      # Create data directory for persistence
      system.activationScripts.createTechnitiumDir = ''
        mkdir -p /var/lib/technitium
        chmod 755 /var/lib/technitium
      '';
      
      # Open required firewall ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 53 80 443 8953 ];
        allowedUDPPorts = [ 53 ];
      };
      
      # Additional packages
      environment.systemPackages = with pkgs; [
        docker-compose
        dig
        whois
      ];
      
      # Setup automatic backup of DNS data
      systemd.services.technitium-backup = {
        description = "Technitium DNS Server Backup";
        after = [ "docker-technitium.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "technitium-backup" ''
            set -euo pipefail
            
            BACKUP_DIR="/var/backups/technitium"
            BACKUP_FILE="$BACKUP_DIR/technitium-$(date +%Y%m%d-%H%M%S).tar.gz"
            
            mkdir -p "$BACKUP_DIR"
            tar -czf "$BACKUP_FILE" -C /var/lib/technitium .
            
            # Keep only the last 7 backups
            ls -t "$BACKUP_DIR"/technitium-*.tar.gz | tail -n +8 | xargs -r rm
          '';
        };
      };
      
      systemd.timers.technitium-backup = {
        wantedBy = [ "timers.target" ];
        partOf = [ "technitium-backup.service" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    }
  ];
}
