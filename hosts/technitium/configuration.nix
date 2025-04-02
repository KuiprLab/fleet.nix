{ config, pkgs, ... }:

{
  imports = [
    ../utils/common.nix
  ];

  # Container specific networking
  networking.hostName = "technitium";
  networking.interfaces.eth0.ipv4.addresses = [
    { address = "10.0.0.10"; prefixLength = 24; }
  ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  
  # Open necessary ports
  networking.firewall.allowedTCPPorts = [ 22 53 5380 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  
  # Technitium DNS Server setup using Docker
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  
  systemd.services.technitium = {
    description = "Technitium DNS Server";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = [
        "${pkgs.docker}/bin/docker pull technitium/dns-server:latest"
        ''${pkgs.bash}/bin/bash -c "${pkgs.docker}/bin/docker rm -f technitium-dns || true"''
      ];
      ExecStart = ''
        ${pkgs.docker}/bin/docker run -d \
          --name technitium-dns \
          --restart unless-stopped \
          -p 5380:5380 \
          -p 53:53/udp \
          -p 53:53/tcp \
          -v technitium-data:/etc/dns \
          technitium/dns-server:latest
      '';
      ExecStop = "${pkgs.docker}/bin/docker stop technitium-dns";
    };
  };
  
  # Add docker group to admin user
  users.users.admin.extraGroups = [ "docker" ];

  # Enable Bento for deployment
  services.bento.enable = true;
  
  # Set system state version
  system.stateVersion = "23.11";
}
