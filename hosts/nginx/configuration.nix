{
  pkgs,
  lib,
  modulesPath,
  config,
  ...
}: let
  # Define a mapping of domains to their target servers and ports
  proxyTargets = {
    "ha.hl.kuipr.de" = {
      ip = "192.168.1.147";
      port = 8123;
    };
    "xdr.hl.kuipr.de" = {
      ip = "192.168.1.2";
      port = 443;
    };
    "pve.hl.kuipr.de" = {
      ip = "192.168.1.85";
      port = 8006;
    };
    "truenas.hl.kuipr.de" = {
      ip = "192.168.1.122";
      port = 443;
    };
    "ui.hl.kuipr.de" = {
      ip = "192.168.1.155";
      port = 844;
    };
  };

  # Function to generate NGINX virtual hosts
  mkVirtualHost = domain: targetConfig: {
    name = domain;
    value = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "https://${targetConfig.ip}:${toString targetConfig.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_pass_header Authorization;
        '';
      };
    };
  };

  # Convert the domain-target mapping to virtual hosts
  virtualHosts =
    lib.mapAttrs'
    (domain: target: mkVirtualHost domain target)
    proxyTargets;

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
      services.nginx = {
        enable = true;
        virtualHosts = virtualHosts; # Use our generated virtualHosts
        statusPage = true; # Enable /nginx_status endpoint
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "me@dinama.dev";
      };

      # Configure Prometheus NGINX exporter
      services.prometheus.exporters.nginx = {
        enable = true;
        scrapeUri = "http://localhost/nginx_status";
        openFirewall = true; # Opens port 9113 for Prometheus server
      };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # Open required ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [80 443 9113 22]; # HTTP, HTTPS, HAProxy stats, SSH
      };

      # Additional packages
      environment.systemPackages = with pkgs; [
        certbot
        openssl
      ];
    }
  ];
}
