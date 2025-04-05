{
  pkgs,
  lib,
  modulesPath,
  config,
  ...
}: let
  domains = [
    "hl.kuipr.de"
    "dns.hl.kuipr.de"
    "ha.hl.kuipr.de"
    "proxy.hl.kuipr.de"
    "pve.hl.kuipr.de"
    "truenas.hl.kuipr.de"
    "xdr.hl.kuipr.de"
  ];
  commonUtils = import ../../utils/common.nix {inherit pkgs;};
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "ha-lxc-haproxy";
      ipAddress = "192.168.1.69";
    })

    {
      services.nginx.enable = true;
      services.nginx.virtualHosts = {

        "xdr.hl.kuipr.de" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://192.168.1.2:443";
            proxyWebsockets = true; # needed if you need to use WebSocket
            extraConfig =
              # required when the target is also TLS server with multiple hosts
              "proxy_ssl_server_name on;"
              +
              # required when the server wants to use HTTP Authentication
              "proxy_pass_header Authorization;";
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "me@dinama.dev";
      };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # Open required ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [80 443 1936 22]; # HTTP, HTTPS, HAProxy stats, SSH
      };

      # Additional packages
      environment.systemPackages = with pkgs; [
        socat # Useful for HAProxy socket commands
        certbot
        openssl
      ];
    }
  ];
}
