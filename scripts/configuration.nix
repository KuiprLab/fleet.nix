{
  config,
  modulesPath,
  pkgs,
  lib,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/proxmox-lxc.nix")];
  nix.settings = {sandbox = false;};
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };
  security.pam.services.sshd.allowNullPassword = true;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
      PermitEmptyPasswords = "yes";
    };
  };
  systemd.mounts = [
    {
      where = "/sys/kernel/debug";
      enable = false;
    }
  ];
  system.stateVersion = "24.11";
}
