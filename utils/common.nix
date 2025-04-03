{ nixpkgs }:

{
  # Common configuration for LXC containersj
  mkLxcConfig = { hostname, ipAddress }: {
    networking = {
      hostName = hostname;
      defaultGateway = "192.168.1.1";
      nameservers = [ "192.168.1.1" ];
      interfaces.eth0 = {
        ipv4.addresses = [{
          address = ipAddress;
          prefixLength = 24;
        }];
      };
    };

            boot.isContainer = true;

    
    # Basic system configuration
    system.stateVersion = "23.11";
    
    # Base system packages
    environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
      git
      vim
      curl
      wget
      htop
      dig
    ];
    
    # Enable SSH for remote access
    services.openssh = {
      enable = true;
      permitRootLogin = "prohibit-password"; 
      passwordAuthentication = false;
    };
    
    # Security hardening
    security = {
      sudo.wheelNeedsPassword = false;  # For automated deployments
      auditd.enable = true;
      audit.enable = true;
    };
    
    # Create a default user with SSH access
    users.users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." 
      ];
    };
    
    # Enable automatic flake updates via cron
    systemd.services.flake-update = {
      description = "Update system from flake";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${nixpkgs.legacyPackages.x86_64-linux.bash}/bin/bash -c 'cd /etc/nixos && ${nixpkgs.legacyPackages.x86_64-linux.git}/bin/git pull && ${nixpkgs.legacyPackages.x86_64-linux.nix}/bin/nix flake update && nixos-rebuild switch --flake .#'";
      };
    };
    
    systemd.timers.flake-update = {
      wantedBy = [ "timers.target" ];
      partOf = [ "flake-update.service" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
