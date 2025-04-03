{
  pkgs,
  ...
}: {
  # Common configuration for LXC containersj
  mkLxcConfig = {
    hostname,
    ipAddress,
  }: {
    networking = {
      hostName = hostname;
      defaultGateway = {
        address = "192.168.1.1";
        interface = "eth0";
      };
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
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
        PermitEmptyPasswords = "yes";
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
        sandbox = false;
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

    # system.autoUpgrade = {
    #   enable = true;
    #   flake = inputs.self.outPath;
    #   flags = [
    #     "--update-input"
    #     "nixpkgs"
    #     "--print-build-logs"
    #   ];
    #   dates = "02:00";
    #   randomizedDelaySec = "45min";
    # };

    # Workaround for https://github.com/NixOS/nixpkgs/issues/157918
    systemd.mounts = [
      {
        where = "/sys/kernel/debug";
        enable = false;
      }
    ];
  };
}
