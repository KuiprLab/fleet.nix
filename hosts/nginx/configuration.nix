{
  pkgs,
  lib,
  modulesPath,
  config,
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

  # Filter only non-SSL targets for Anubis
  anubisTargets = lib.filterAttrs (_: v: v.isSSL == false) proxyTargets;

  # Create Anubis instances only for those
  anubisInstances =
    lib.mapAttrs'
    (domain: target: {
      name = lib.strings.sanitizeDerivationName domain;
      value = {
        settings = {
          TARGET = "http://${target.ip}:${toString target.port}";
          USE_REMOTE_ADDRESS = true;
          TARGET_INSECURE_SKIP_VERIFY = true;
        };
      };
    })
    anubisTargets;

  # Function to generate NGINX virtual hosts with Anubis protection
  mkVirtualHost = domain: targetConfig: {
    name = domain;
    value = {
      enableACME = true;
      forceSSL = true;
      locations."/" = let
        sanitizedName = lib.strings.sanitizeDerivationName domain;
        proxyPassUrl =
          if targetConfig.isSSL
          then "https://${targetConfig.ip}:${toString targetConfig.port}"
          else "http://unix:${config.services.anubis.instances.${sanitizedName}.settings.BIND}";
      in {
        proxyPass = proxyPassUrl;
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

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-haproxy";
      ipAddress = "192.168.1.69";
    })
    {
      services.tailscale.enable = true;
      # Enable and configure networkd-dispatcher for persistent ethtool settings
      services.networkd-dispatcher.enable = true;

      # Provide a dispatcher script for UDP offload tuning
      environment.etc."networkd-dispatcher/routable.d/50-tailscale".text = ''
        #!/bin/sh

        NETDEV="$(ip -o route get 8.8.8.8 | awk '{print $5}')"
        if [ -n "$NETDEV" ]; then
          /run/wrappers/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        fi
      '';

      # Ensure the script is executable
      systemd.tmpfiles.rules = [
        "f /etc/networkd-dispatcher/routable.d/50-tailscale 0755 root root"
      ];

      # Enable IP forwarding
      networking.enableIPv6 = true; # If needed
      networking.nat.enable = true;

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
      # Enable Anubis with instances for each domain
      services.anubis = {
        defaultOptions = {
          # Default configuration for all anubis instances
          settings = {
            DIFFICULTY = 4; # Default challenge difficulty
            SERVE_ROBOTS_TXT = true; # Serve default robots.txt that blocks AI bots
          };
        };
        instances = anubisInstances;
      };

      # Configure nginx service
      services.nginx = {
        enable = true;
        virtualHosts = virtualHosts;
        statusPage = true; # Enable /nginx_status endpoint
      };

      # Add nginx user to anubis group for socket access
      users.users.nginx.extraGroups = [config.users.groups.anubis.name];

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
        ethtool
      ];
    }
  ];
}
