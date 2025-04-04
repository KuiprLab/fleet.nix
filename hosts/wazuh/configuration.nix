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
      hostname = "bind";
      ipAddress = "192.168.1.70";
    })
    {
      programs.wazuh = {
        enable = true;
        username = "daniel";
        hashedPassword = "$2a$10$CvmkwWOLj0ThTVnKLEM5neZOWS5GZ7cZQBIXvL/fs6keSnU15C/DG";
      };

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
