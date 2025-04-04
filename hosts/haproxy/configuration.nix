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
      # HAProxy configuration
      services.haproxy = {
        enable = true;
        config = builtins.readFile ./haproxy.cfg;
      };

      # ACME/Let's Encrypt for automatic SSL certificates
      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@kuipr.de";
        certs = {
          "hl.kuipr.de" = {
            extraDomainNames = builtins.filter (d: d != "hl.kuipr.de") domains;
            dnsProvider = "cloudflare";
            credentialsFile = "/var/lib/secrets/cloudflare.env";
            dnsPropagationCheck = true;
            webroot = null; # Use DNS challenge instead of HTTP
            group = "haproxy"; # Allow HAProxy to read certificates
          };
        };
      };

      # Create combined certificate and key file for HAProxy
      systemd.services.haproxy-ssl-setup = {
        description = "Prepare SSL Certificates for HAProxy";
        after = [ "acme-hl.kuipr.de.service" ];
        wants = [ "acme-hl.kuipr.de.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "setup-haproxy-ssl" ''
            set -e
            mkdir -p /etc/ssl/private
            cat /var/lib/acme/hl.kuipr.de/fullchain.pem /var/lib/acme/hl.kuipr.de/key.pem > /etc/ssl/private/hl.kuipr.de.pem
            chmod 640 /etc/ssl/private/hl.kuipr.de.pem
            chown root:haproxy /etc/ssl/private/hl.kuipr.de.pem
          '';
        };
      };
      
      # Create this directory to store ACME secrets
      systemd.tmpfiles.rules = [
        "d /var/lib/secrets 0750 root root -"
      ];

      # Let's also configure SSH certificates through ACME for convenience
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        # Use ACME certificate for SSH
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_rsa_key";
            type = "rsa";
            bits = 4096;
          }
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };

      # Auto-renewal hook to restart HAProxy when certificates are renewed
      security.acme.defaults.reloadServices = [ "haproxy" ];

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
        haproxy
        socat # Useful for HAProxy socket commands
        certbot
        openssl
      ];
      
      # Instructions for post-installation setup
      system.activationScripts.haproxySetupInstructions = ''
        echo "==============================================================="
        echo "HAProxy Configuration with Automatic SSL Setup"
        echo "==============================================================="
        echo ""
        echo "IMPORTANT: Before running this configuration, create the following file:"
        echo "/var/lib/secrets/cloudflare.env with the following content:"
        echo ""
        echo "CLOUDFLARE_EMAIL=your-cloudflare-email@example.com"
        echo "CLOUDFLARE_API_KEY=your-global-api-key"
        echo ""
        echo "Then run: systemctl restart acme-hl.kuipr.de.service"
        echo "==============================================================="
      '';
    }
  ];
}
