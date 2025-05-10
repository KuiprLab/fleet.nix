{
  pkgs,
  lib,
  modulesPath,
  config,
  ...
}: let
  # Define a mapping of domains to their target servers and ports
  proxyTargets = {
    "xdr.hl.kuipr.de" = {
      ip = "192.168.1.2";
      port = 443;
      isSSL = true;
    };
    "pve.hl.kuipr.de" = {
      ip = "192.168.1.85";
      port = 8006;
      isSSL = true;
    };
    "truenas.hl.kuipr.de" = {
      ip = "192.168.1.122";
      port = 443;
      isSSL = false;
    };
    "ui.hl.kuipr.de" = {
      ip = "192.168.1.155";
      port = 844;
      isSSL = true;
    };
    "hb.hl.kuipr.de" = {
      ip = "192.168.1.10";
      port = 8581;
      isSSL = false;
    };
  };

  # Function to generate Anubis instance configuration for each domain
  mkAnubisInstance = domain: targetConfig: {
    name = lib.replaceStrings ["."] ["-"] domain;
    value = {
      settings = {
        TARGET = "http${if targetConfig.isSSL then "s" else ""}://${targetConfig.ip}:${toString targetConfig.port}";
        # Use Unix domain sockets for communication between Nginx and Anubis
        BIND = "/run/anubis/${lib.replaceStrings ["."] ["-"] domain}.sock";
        BIND_NETWORK = "unix";
        # Expose metrics on a unique port
        METRICS_BIND = "127.0.0.1:${toString (9200 + lib.attrsets.attrValues (lib.mapAttrsToList (name: _: if name == domain then 1 else 0) proxyTargets))}";
        METRICS_BIND_NETWORK = "tcp";
        DIFFICULTY = 3; # Adjust the challenge difficulty as needed
      };
      # Customize bot policy if needed
      botPolicy = {
        dnsbl = true;
        bots = {
          good = [
          ];
          bad = [
            "GoogleBot"
            "BingBot"
            "DuckDuckBot"
            "YandexBot"
            "OpenAI"
            "Anthropic"
            "Claude"
            "GPTBot"
            "CCBot"
            "FacebookBot"
          ];
        };
      };
    };
  };

  # Generate Anubis instances for all domains
  anubisInstances = lib.mapAttrs' mkAnubisInstance proxyTargets;

  # Function to generate NGINX virtual hosts with Anubis protection
  mkVirtualHost = domain: targetConfig: {
    name = domain;
    value = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        # Proxy to the Anubis instance instead of directly to the target
        proxyPass = "http://unix:${config.services.anubis.instances.${lib.replaceStrings ["."] ["-"] domain}.settings.BIND}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_pass_header Authorization;
        '';
      };
    };
  };

  # Convert the domain-target mapping to virtual hosts
  virtualHosts = lib.mapAttrs' mkVirtualHost proxyTargets;
  
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
      # Configure Anubis with our generated instances
      services.anubis = {
        enable = true;
        # Default options for all Anubis instances
        defaultOptions = {
          settings = {
            LOG_LEVEL = "info";
            COUNTRY_BLOCK = "off"; # Optional: You can enable country blocking if needed
          };
        };
        instances = anubisInstances;
      };

      # Add nginx user to the anubis group to access the UNIX sockets
      users.users.nginx.extraGroups = [ config.users.groups.anubis.name ];

      services.nginx = {
        enable = true;
        virtualHosts = virtualHosts;
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

      # Configure Prometheus Anubis exporter for metrics collection from all instances
      services.prometheus.exporters.anubis = {
        enable = true;
        port = 9114;
        openFirewall = true;
      };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # Open required ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          80   # HTTP
          443  # HTTPS
          9113 # NGINX metrics
          9114 # Anubis metrics
          22   # SSH
        ];
      };

      # Additional packages
      environment.systemPackages = with pkgs; [
        certbot
        openssl
      ];
    }
  ];
}
