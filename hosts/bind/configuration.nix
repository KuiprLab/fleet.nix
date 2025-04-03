# hosts/bind/configuration.nix
{ pkgs, lib, modulesPath, config, ... }:

let
  commonUtils = import ../../utils/common.nix { inherit pkgs; };
  sshAuth = import ../../utils/ssh-auth.nix { inherit pkgs lib config; };
  
  # Define zones
  primaryZones = {
    "example.com" = {
      file = "/var/lib/bind/example.com.zone";
      master = true;
    };
    "1.168.192.in-addr.arpa" = {
      file = "/var/lib/bind/192.168.1.rev";
      master = true;
    };
  };
  
  # Sample zone file content
  exampleZoneFile = pkgs.writeText "example.com.zone.template" ''
    $TTL 86400
    @ IN SOA ns1.example.com. admin.example.com. (
         2023041001 ; Serial
         3600       ; Refresh
         1800       ; Retry
         604800     ; Expire
         86400      ; Minimum TTL
    )
    
    ; Name servers
    @        IN NS     ns1.example.com.
    
    ; A records
    ns1      IN A      10.0.0.11
    www      IN A      192.168.1.100
    app      IN A      192.168.1.101
    
    ; CNAME records
    mail     IN CNAME  app
  '';
  
  # Sample reverse zone file
  reverseZoneFile = pkgs.writeText "192.168.1.rev.template" ''
    $TTL 86400
    @ IN SOA ns1.example.com. admin.example.com. (
         2023041001 ; Serial
         3600       ; Refresh
         1800       ; Retry
         604800     ; Expire
         86400      ; Minimum TTL
    )
    
    ; Name servers
    @        IN NS     ns1.example.com.
    
    ; PTR records
    11       IN PTR    ns1.example.com.
    100      IN PTR    www.example.com.
    101      IN PTR    app.example.com.
  '';
  
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "bind";
      ipAddress = "10.0.0.11"; # Same IP as technitium had
    })
    
    # Add secure SSH configuration
    sshAuth.mkSecureSSHConfig
    
    {
      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };
      
      # BIND DNS server configuration
      services.bind = {
        enable = true;
        
        # Configure as a caching name server
        cacheNetworks = [ "192.168.1.0/24" "10.0.0.0/24" "127.0.0.0/8" ];
        ipv4Only = true;
        
        # Forward queries we can't resolve to external DNS
        forwarders = [ "1.1.1.1" "8.8.8.8" ];
        
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
        if [ ! -f /var/lib/bind/example.com.zone ]; then
          cp ${exampleZoneFile} /var/lib/bind/example.com.zone
          chown named:named /var/lib/bind/example.com.zone
        fi
        
        if [ ! -f /var/lib/bind/192.168.1.rev ]; then
          cp ${reverseZoneFile} /var/lib/bind/192.168.1.rev
          chown named:named /var/lib/bind/192.168.1.rev
        fi
      '';
      
      # Open required firewall ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [53];
        allowedUDPPorts = [53];
      };
      
      # Web-based DNS administration (optional)
      services.webmin = {
        enable = true;
        port = 10000;
        ssl = true;
        interface = "0.0.0.0";
        extraModules = ["bind"];
      };
      
      # Open Webmin port if enabled
      networking.firewall.allowedTCPPorts = lib.mkIf config.services.webmin.enable [ 
        config.services.webmin.port 
      ];
      
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
      
      # Additional monitoring tools
      environment.systemPackages = with pkgs; [
        dig
        whois
        ldns # For drill command
        bind.dnsutils
        webmin # Makes it easier to get the webmin password
      ];
    }
  ];
}
