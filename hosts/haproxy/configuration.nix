{
  pkgs,
  lib,
  modulesPath,
  config,
  ...
}: let
  haproxyConfig = ./haproxy.cfg;
  commonUtils = import ../../utils/common.nix {inherit pkgs;};
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Use the common configuration for LXC containers
  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-haproxy";
      ipAddress = "192.168.1.69"; # Update with your actual IP
    })
    
    {
      # HAProxy specific configuration
      services.haproxy = {
        enable = true;
        config = builtins.readFile haproxyConfig;
      };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      # Open required ports
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [80 443 1936 22]; # HTTP, HTTPS, HAProxy stats
      };

      # Additional packages
      environment.systemPackages = with pkgs; [
        haproxy
        socat # Useful for HAProxy socket commands
      ];
    }
  ];
}
