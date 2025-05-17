{
  pkgs,
  lib,
  modulesPath,
  ...
}: let
  # Define a mapping of domains to their target servers and ports
  proxyTargets = {
    "xdr.internal.kuipr.de" = {
      ip = "192.168.1.2";
      port = 443;
      isSSL = true;
    };
    "pve.internal.kuipr.de" = {
      ip = "192.168.1.85";
      port = 8006;
      isSSL = true;
    };
    "truenas.internal.kuipr.de" = {
      ip = "192.168.1.122";
      port = 443;
      isSSL = true;
    };
    "ui.internal.kuipr.de" = {
      ip = "192.168.1.155";
      port = 844;
      isSSL = true;
    };
    "hb.internal.kuipr.de" = {
      ip = "192.168.1.10";
      port = 8581;
      isSSL = false;
    };
  };

  # Function to generate NGINX virtual hosts
  mkVirtualHost = domain: targetConfig: {
    name = domain;
    value = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass =
          if targetConfig.isSSL
          then "https://${targetConfig.ip}:${toString targetConfig.port}"
          else "http://${targetConfig.ip}:${toString targetConfig.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_pass_header Authorization;
        '';
      };
    };
  };

  # Convert the domain-target mapping to virtual hosts
  virtualHosts = lib.mapAttrs' (domain: target: mkVirtualHost domain target) proxyTargets;

  commonUtils = import ../../utils/common.nix {inherit pkgs;};
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-haproxy";
      ipAddress = "192.168.1.69";
    })
    {
      services.tailscale.enable = true;
      services.networkd-dispatcher.enable = true;

      environment.etc."networkd-dispatcher/routable.d/50-tailscale".text = ''
        #!/bin/sh

        NETDEV="$(ip -o route get 8.8.8.8 | awk '{print $5}')"
        if [ -n "$NETDEV" ]; then
          /run/wrappers/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        fi
      '';

      systemd.tmpfiles.rules = [
        "f /etc/networkd-dispatcher/routable.d/50-tailscale 0755 root root"
      ];

      networking.enableIPv6 = true;
      networking.nat.enable = true;

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      services.nginx = {
        enable = true;
        virtualHosts = virtualHosts;
        statusPage = true;
      };

      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "me@dinama.dev";
          dnsProvider = "hetzner";
          credentialsFile = "/etc/letsencrypt/hetzner-api.env";
          dnsPropagationCheck = true;
          renewInterval = "daily";
        };
      };

      services.prometheus.exporters.nginx = {
        enable = true;
        scrapeUri = "http://localhost/nginx_status";
        openFirewall = true;
      };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [80 443 9113 22];
      };

      environment.systemPackages = with pkgs; [
        certbot
        openssl
        ethtool
      ];
    }
  ];
}
