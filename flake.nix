{
  description = "Flake for Bento Master System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bento.url = "github:rapenne-s/bento";
  };

  outputs = { self, nixpkgs, bento }: {
    nixosConfigurations.hl-lxc-bento-master = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ config, modulesPath, pkgs, lib, ... }: {
          imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
          
          nix.settings = { sandbox = false; };
          
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
          
          system.stateVersion = "24.11";
          
          fileSystems."/" = {
            device = "/dev/vda1";
            fsType = "ext4";
          };

          environment.systemPackages = with pkgs; [
            bento.packages.x86_64-linux.default
            jq
            git
          ];

          nix.settings.experimental-features = [ "nix-command" "flakes" ];
        })
      ];
    };
  };
}

