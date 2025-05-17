# Auto-generated using compose2nix v0.3.2-pre.
{
  pkgs,
  lib,
  config,
  modulesPath,
  ...
}: let
  commonUtils = import ../../utils/common.nix {inherit pkgs;};
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../utils/my-declared-folders.nix
  ];

  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-homebridge";
      ipAddress = "192.168.1.213";
    })

    {
      networking.firewall = {
        enable = false;
        allowedTCPPorts = [8443 22]; # HTTP, HTTPS, HAProxy stats, SSH
      };

      services.networking.unifi = {
        enable = true;
        openFirewall = true;
      };
    }
  ];
}
