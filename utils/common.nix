{pkgs}: {
  # Common configuration for LXC containersj
  mkLxcConfig = {
    hostname,
    ipAddress,
  }: {
    networking = {
      hostName = hostname;
      defaultGateway = "192.168.1.1";
      nameservers = ["192.168.1.1"];
      interfaces.eth0 = {
        ipv4.addresses = [
          {
            address = ipAddress;
            prefixLength = 24;
          }
        ];
      };
    };

    boot.isContainer = true;

    # Basic system configuration
    system.stateVersion = "23.11";

    # Base system packages
    environment.systemPackages = with pkgs; [
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
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };

    # Security hardening
    security = {
      sudo.wheelNeedsPassword = false; # For automated deployments
      auditd.enable = true;
    };

    # Create a default user with SSH access
    users.users.admin = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = [
        # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
      ];
    };

    nix = {
      settings = {
        # Add Cachix binary caches (replace "your-cache" with your Cachix cache name)
        trusted-binary-caches = [
          "https://cache.nixos.org/"
        ];

        substituters = [
          "https://cache.nixos.org"
          # nix community's cache server
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };

    # Enable automatic flake updates via cron
    systemd.services.flake-update = {
      description = "Update system from flake";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'cd /etc/nixos && ${pkgs.git}/bin/git pull && ${pkgs.nix}/bin/nix flake update && nixos-rebuild switch --flake .#'";
      };
    };

    # Woraround for https://github.com/NixOS/nixpkgs/issues/157918
    systemd.mounts = [
      {
        where = "/sys/kernel/debug";
        enable = false;
      }
    ];

    systemd.timers.flake-update = {
      wantedBy = ["timers.target"];
      partOf = ["flake-update.service"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
