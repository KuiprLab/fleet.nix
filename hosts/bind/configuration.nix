# hosts/bind/configuration.nix
{
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  commonUtils = import ../../utils/common.nix {inherit pkgs;};

  # Define zones
  primaryZones = {
    "hl.kuipr.de" = {
      file = "/var/lib/bind/hl.kuipr.de.zone";
      master = true;
    };
    "1.168.192.in-addr.arpa" = {
      file = "/var/lib/bind/192.168.1.rev";
      master = true;
    };
  };

  # Zone file content for your actual domain
  hlKuiprDeZoneFile = pkgs.writeText "hl.kuipr.de.zone.template" ''
    $TTL 86400
    @ IN SOA ns1.hl.kuipr.de. admin.hl.kuipr.de. (
         2023041001 ; Serial
         3600       ; Refresh
         1800       ; Retry
         604800     ; Expire
         86400      ; Minimum TTL
    )

    ; Name servers
    @        IN NS     ns1.hl.kuipr.de.
    ns1      IN A      192.168.1.70

    ; NGINX reverse proxy server
    nginx    IN A      192.168.1.69

    ; Wildcard record - any undefined subdomain will resolve to nginx
    *        IN A      192.168.1.69
  '';

  # Reverse zone file
  reverseZoneFile = pkgs.writeText "192.168.1.rev.template" ''
    $TTL 86400
    @ IN SOA ns1.hl.kuipr.de. admin.hl.kuipr.de. (
         2023041001 ; Serial
         3600       ; Refresh
         1800       ; Retry
         604800     ; Expire
         86400      ; Minimum TTL
    )

    ; Name servers
    @        IN NS     ns1.hl.kuipr.de.

    ; PTR records
    70       IN PTR    ns1.hl.kuipr.de.
    69       IN PTR    nginx.hl.kuipr.de.
    147      IN PTR    ha.hl.kuipr.de.
    2        IN PTR    xdr.hl.kuipr.de.
    85       IN PTR    pve.hl.kuipr.de.
    122      IN PTR    truenas.hl.kuipr.de.
    155      IN PTR    ui.hl.kuipr.de.
  '';
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-bind";
      ipAddress = "192.168.1.70";
    })

    {
      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # BIND DNS server configuration
      services.bind = {
        enable = true;

        # Configure as a caching name server
        cacheNetworks = ["192.168.1.0/24" "10.0.0.0/24" "127.0.0.0/8"];
        ipv4Only = true;

        # Forward queries we can't resolve to external DNS
        forwarders = ["1.1.1.1" "8.8.8.8"];

        # Configure zones
        zones = primaryZones;

        # Extra configuration
        extraOptions = ''
          dnssec-validation auto;
          recursion yes;
          allow-recursion { cacheNetworks; };
          listen-on { any; };

          # Query logging (useful for debugging)
          querylog yes;
        '';
      };

      # Create required zone files from templates
      system.activationScripts.createBindZones = ''
        # Create zone directory if it doesn't exist
        mkdir -p /var/lib/bind
        chown named:named /var/lib/bind

        # Create zone files from templates if they don't exist
        if [ ! -f /var/lib/bind/hl.kuipr.de.zone ]; then
          cp ${hlKuiprDeZoneFile} /var/lib/bind/hl.kuipr.de.zone
          chown named:named /var/lib/bind/hl.kuipr.de.zone
        fi

        if [ ! -f /var/lib/bind/192.168.1.rev ]; then
          cp ${reverseZoneFile} /var/lib/bind/192.168.1.rev
          chown named:named /var/lib/bind/192.168.1.rev
        fi
      '';

      # Open required firewall ports
      networking.firewall = {
        enable = true;
        allowedUDPPorts = [53];
        allowedTCPPorts = [22 53 9119]; # Added 9119 for Prometheus BIND exporter
      };

      # Setup automatic backup of DNS data
      systemd.services.bind-backup = {
        description = "BIND DNS Server Backup";
        after = ["bind.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "bind-backup" ''
            set -euo pipefail

            BACKUP_DIR="/var/backups/bind"
            BACKUP_FILE="$BACKUP_DIR/bind-$(date +%Y%m%d-%H%M%S).tar.gz"

            mkdir -p "$BACKUP_DIR"
            tar -czf "$BACKUP_FILE" -C /var/lib/bind .

            # Keep only the last 7 backups
            ls -t "$BACKUP_DIR"/bind-*.tar.gz | tail -n +8 | xargs -r rm
          '';
        };
      };

      systemd.timers.bind-backup = {
        wantedBy = ["timers.target"];
        partOf = ["bind-backup.service"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

      # Configure Prometheus BIND exporter
      services.prometheus.exporters.bind = {
        enable = true;
        bindURI = "127.0.0.1";
        port = 8053;
        openFirewall = true; # Opens port 9119 for Prometheus server
      };

      # Enable statistics in BIND for the exporter
      services.bind.extraConfig = ''
        statistics-channels {
          inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
        };
      '';

      # Additional monitoring tools
      environment.systemPackages = with pkgs; [
        dig
        whois
        ldns # For drill command
        bind.dnsutils
      ];
    }
  ];
}
