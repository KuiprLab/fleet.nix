{
  pkgs,
  inputs,
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
      nameservers = ["192.168.1.70" "9.9.9.9"];
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
    users.users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMMwDw4fCT/0NrKRzqWESu3Swz+qlPw+cv28LoRb2EzzY1spVhN0LzjZZGTDa/b1pQtssws4tKjGEDc1NZbOkIFqU/tGmGD6V5hFd+c/F87zzt5aOkrMF7BWEmZOESqFffE5HwFb6H/TQG4LrJAmPC4YiSdvjMogIBxrlse0ZRHQ6ZUSfmZ9/ZroBASjfqnCiuJSw/niWPGxgaq0Xi1tSYwmfdzOZ+4QBpbm2/4NiInk7ww/esssbfUw1tIQD9dL7C1qSiJmKIs7PBQfpPofwYFg/k+s6BIOWV/s54oFrUyivE8NP1g7x15VR7s4GwxhZ+I+Z6LZtaBZPVugb/h/af"
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

    # Workaround for https://github.com/NixOS/nixpkgs/issues/157918
    systemd.mounts = [
      {
        where = "/sys/kernel/debug";
        enable = false;
      }
    ];
  };
}
