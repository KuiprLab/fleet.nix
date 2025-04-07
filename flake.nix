{
  description = "NixOS configurations for homelab LXC containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # For automatic deployments
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    wazuh.url = "github:anotherhadi/wazuh-nix";
  };

  outputs = {
    self,
    nixpkgs,
    deploy-rs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    # Common modules for all hosts
    commonModules = [
      ./utils/auto-update.nix
    ];
  in {
    # NixOS configurations for each host
    nixosConfigurations = {
      hl-lxc-nginx = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = {inherit self;};
        modules =
          commonModules
          ++ [
            ./hosts/nginx/configuration.nix
          ];
      };
      hl-lxc-bind = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = {inherit self;};
        modules =
          commonModules
          ++ [
            ./hosts/bind/configuration.nix
          ];
      };

      hl-lxc-wazuh = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = {inherit self;};
        modules =
          commonModules
          ++ [
            ./hosts/wazuh/configuration.nix
            inputs.wazuh.nixosModules.wazuh
          ];
      };
    };

    # Deployment configuration using deploy-rs
    deploy.nodes = {
      hl-lxc-nginx = {
        hostname = "192.168.1.69";
        profiles.system = {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hl-lxc-nginx;
        };
      };

      hl-lxc-bind = {
        hostname = "192.168.1.70";
        profiles.system = {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hl-lxc-bind;
        };
      };

      hl-lxc-wazuh = {
        hostname = "192.168.1.2";
        profiles.system = {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hl-lxc-wazuh;
        };
      };
    };

    # Check deployments
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

    # Set a formatter for both the system architectures im using
    formatter = {
      aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
      x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    };
  };
}
