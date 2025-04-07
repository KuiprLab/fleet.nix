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
  ];

  config = lib.mkMerge [
    (commonUtils.mkLxcConfig {
      hostname = "hl-lxc-wazuh";
      ipAddress = "192.168.1.2";
    })
    {

      programs.wazuh.enable = true;

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
