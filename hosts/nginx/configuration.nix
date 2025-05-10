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
      enable = true;
      settings = {
        # Configure target service
        TARGET = "http${if targetConfig.isSSL then "s" else ""}://${targetConfig.ip}:${toString targetConfig.port}";
        
        # Use Unix domain sockets for communication between Nginx and Anubis
        # These are automatically configured with proper permissions
        BIND = "/run/anubis/anubis-${lib.replaceStrings ["."] ["-"] domain}.sock";
        BIND_NETWORK = "unix";
        
        # Expose metrics on a unique port for this service
        METRICS_BIND = "127.0.0.1:${toString (9200 + lib.attrsets.elemAt (lib.attrNames proxyTargets) (lib.attrsets.attrValues (lib.mapAttrsToList (name: _: if name == domain then 1 else 0) proxyTargets)))}";
        METRICS_BIND_NETWORK = "tcp";
        
        # Set challenge difficulty
        DIFFICULTY = 3;
        
        # Add service-specific settings here if needed
        SERVE_ROBOTS_TXT = true;
      };
      
      # Customize bot policy
      botPolicy = {
        # Basic settings
        dnsbl = true;
        country_block = "off";
        
        # Bot definitions
        bots = {
          good = [
            "GoogleBot"
            "BingBot"
            "DuckDuckBot"
            "YandexBot"
            "BaiduSpider"
            "PingdomBot"
            "SlackBot"
          ];
          bad = [
            "OpenAI"
            "Anthropic"
            "Claude"
            "GPTBot"
            "CCBot"
            "FacebookBot"
            "CommonCrawl"
            "AhrefsBot"
          ];
        };
        
        # Challenge tuning
        challenge = {
          enabled = true;
          max_age = 3600;
          threshold = 60;
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
        proxyPass = "http://unix:/run/anubis/anubis-${lib.replaceStrings ["."] ["-"] domain}.sock";
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
        # Default options for all Anubis instances
        defaultOptions = {
          settings = {
            # Global Anubis settings
            LOG_LEVEL = "info";
            SOCKET_MODE = "0770";  # Allow access to sockets by group
          };
          # Extra command-line flags if needed
          extraFlags = [];
        };
        
        # Apply all our Anubis instances
        instances = anubisInstances;
      };

      # Add nginx user to the anubis group so it can access the UNIX sockets
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
          22   # SSH
        ];
        # We're also opening the Anubis metrics ports in the 9200+ range
        allowedTCPPortRanges = [
          { from = 9200; to = 9205; } # Anubis metrics ports
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
