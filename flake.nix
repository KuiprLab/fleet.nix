{
  description = "NixOS configurations for homelab LXC containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # For automatic deployments
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    deploy-rs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    # Common modules for all hosts
    commonModules = [
      ./utils/auto-update.nix
    ];
  in {
    # NixOS configurations for each host
    nixosConfigurations = {
      hl-lxc-haproxy = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = {inherit self;};
        modules =
          commonModules
          ++ [
            ./hosts/haproxy/configuration.nix
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
    };

    # Deployment configuration using deploy-rs
    deploy.nodes = {
      hl-lxc-haproxy = {
        hostname = "192.168.1.69";
        profiles.system = {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hl-lxc-haproxy;
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
