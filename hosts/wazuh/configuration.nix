{modulesPath,...}:{

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];
  programs.wazuh = {
        enable = true;
    username = "daniel";
        hashedPassword = "$2a$10$CvmkwWOLj0ThTVnKLEM5neZOWS5GZ7cZQBIXvL/fs6keSnU15C/DG";
    };

      proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
      };
}
