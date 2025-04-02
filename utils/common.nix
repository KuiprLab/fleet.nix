# Common configuration for all containers
{ config, pkgs, ... }:

{
  imports = [
    ./bento.nix
  ];
  
  # Base system configuration
  boot.isContainer = true;
  networking.useDHCP = false;
  networking.firewall.enable = true;
  
  # Enable SSH for remote management
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };
  
  # Common system packages
  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    htop
    git
    tmux
  ];
  
  # User administration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
    ];
  };
}
