{ pkgs, lib, modulesPath, config, ... }: let
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
      isSSL = true;
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

  # Generate anubis instances for each domain
  mkAnubisInstance = domain: targetConfig: if targetConfig.isSSL then null else {
    name = lib.strings.sanitizeDerivationName domain;
    value = {
      settings = {
        TARGET = "http${if targetConfig.isSSL then "s" else ""}://${targetConfig.ip}:${toString targetConfig.port}";
        USE_REMOTE_ADDRESS = true;
        TARGET_INSECURE_SKIP_VERIFY = true;
      };
    };
  };

  # Create anubis instances for each domain, excluding those with isSSL = true
  anubisInstances = lib.filterAttrs (domain: target: target.isSSL == false) proxyTargets;

  # Function to generate NGINX virtual hosts with Anubis protection
  mkVirtualHost = domain: targetConfig: {
    name = domain;
    value = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        # Connect to the Anubis instance for this domain via Unix socket
        proxyPass = "http://unix:${config.services.anubis.instances.${lib.strings.sanitizeDerivationName domain}.settings.BIND}";
        proxyWebsockets = true;
        extraConfig = ''
          # These settings ensure proper forwarding through Anubis
          proxy_ssl_server_name on;
          proxy_pass_header Authorization;
        '';
      };
    };
  };

  # Convert the domain-target mapping to virtual hosts
  virtualHosts = lib.mapAttrs' (domain: target: mkVirtualHost domain target) proxyTargets;

  commonUtils = import ../../utils/common.nix { inherit pkgs; };

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
      # Enable Anubis with instances for each domain
      services.anubis = {
        defaultOptions = {
          # Default configuration for all anubis instances
          settings = {
            DIFFICULTY = 4;  # Default challenge difficulty
            SERVE_ROBOTS_TXT = true;  # Serve default robots.txt that blocks AI bots
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
      users.users.nginx.extraGroups = [ config.users.groups.anubis.name ];

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
        allowedTCPPorts = [ 80 443 9113 22 ]; # HTTP, HTTPS, HAProxy stats, SSH
      };

      # Additional packages
      environment.systemPackages = with pkgs; [
        certbot
        openssl
      ];
    }
  ];
}
