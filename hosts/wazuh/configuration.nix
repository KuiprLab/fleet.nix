{
  modulesPath,
  pkgs,
  lib,
  ...
}: let
  commonUtils = import ../../utils/common.nix {inherit pkgs;};
in {
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
        ./wazuh.nix
  ];

  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "bind";
      ipAddress = "192.168.1.70";
    })
    {

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };

      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
      };

      environment.systemPackages = with pkgs; [
        docker-compose
      ];
    }
  ];
}
