{ config, pkgs, lib, ... }@args:

let
  utils = args.utils;
  haproxyConfig = ./haproxy.cfg;
in {
  imports = [
    # You can import hardware-specific configurations here
  ];
  
  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (utils.mkLxcConfig {
      hostname = "haproxy";
      ipAddress = "192.168.1.69";  # Update with your actual IP
    })
    {
      # HAProxy specific configuration
      services.haproxy = {
        enable = true;
        config = builtins.readFile haproxyConfig;
      };
      
      # Open required ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 80 443 1936 ];  # HTTP, HTTPS, HAProxy stats
      };
      
      # Additional packages
      environment.systemPackages = with pkgs; [
        haproxy
        socat  # Useful for HAProxy socket commands
      ];
      
      # Enable Prometheus metrics for monitoring
      services.prometheus.exporters.haproxy = {
        enable = true;
        scrapeUri = "http://localhost:1936/metrics";
      };
      
      # Add a systemd service for health checking
      systemd.services.haproxy-healthcheck = {
        description = "HAProxy Health Check";
        after = [ "haproxy.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:1936/stats";
        };
      };
      
      # Setup a timer to check health periodically
      systemd.timers.haproxy-healthcheck = {
        wantedBy = [ "timers.target" ];
        partOf = [ "haproxy-healthcheck.service" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
        };
      };
    }
  ];
}
