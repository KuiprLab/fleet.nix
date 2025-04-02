{ config, pkgs, ... }:

{
  imports = [
    ../utils/common.nix
  ];

  # Container specific networking
  networking.hostName = "haproxy";
  networking.interfaces.eth0.ipv4.addresses = [
    { address = "10.0.0.11"; prefixLength = 24; }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [ "10.0.0.10" "1.1.1.1" ];
  
  # Open necessary ports
  networking.firewall.allowedTCPPorts = [ 22 80 443 8404 ];
  
  # HAProxy configuration
  services.haproxy = {
    enable = true;
    config = builtins.readFile ../utils/haproxy-config.cfg;
  };

  # Enable Bento for deployment
  services.bento.enable = true;
  
  # Set system state version
  system.stateVersion = "23.11";
}
