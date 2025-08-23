{
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  commonUtils = import ../../utils/common.nix {inherit pkgs;};

  # Only serve the internal.kuipr.de zone
  primaryZones = {
    "internal.kuipr.de" = {
      file = "/var/lib/bind/internal.kuipr.de.zone";
      master = true;
    };
  };

  # Zone file for internal.kuipr.de
  internalZoneFile = pkgs.writeText "internal.kuipr.de.zone.template" ''
    $TTL 86400
    @ IN SOA ns1.internal.kuipr.de. admin.internal.kuipr.de. (
         2025051101 ; Serial
         3600       ; Refresh
         1800       ; Retry
         604800     ; Expire
         86400      ; Minimum TTL
    )

    ; Name server
    @    IN NS     ns1.internal.kuipr.de.
    ns1  IN A      192.168.1.70

    ; Wildcard record
    *    IN A      192.168.1.69
  '';
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

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

      services.bind = {
        enable = true;
        cacheNetworks = ["192.168.1.0/24" "10.0.0.0/24" "127.0.0.0/8"];
        ipv4Only = true;
        forwarders = ["1.1.1.1" "8.8.8.8"];
        zones = primaryZones;
        extraOptions = ''
          dnssec-validation auto;
          recursion yes;
          allow-recursion { cacheNetworks; };
          listen-on { any; };
          querylog yes;
        '';
      };

      system.activationScripts.createBindZones = ''
        mkdir -p /var/lib/bind
        chown named:named /var/lib/bind

        # Create internal zone file if it doesn't exist
        if [ ! -f /var/lib/bind/internal.kuipr.de.zone ]; then
          cp ${internalZoneFile} /var/lib/bind/internal.kuipr.de.zone
          chown named:named /var/lib/bind/internal.kuipr.de.zone
        fi
      '';

      networking.firewall = {
        enable = true;
        allowedUDPPorts = [53];
        allowedTCPPorts = [22 53 9119 8053];
      };

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

      services.prometheus.exporters.bind = {
        enable = true;
        bindURI = "127.0.0.1";
        port = 8053;
        openFirewall = true;
      };

      services.bind.extraConfig = ''
        statistics-channels {
          inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
        };
      '';

      environment.systemPackages = with pkgs; [
        dig
        whois
        ldns
        bind.dnsutils
      ];
    }
  ];
}
