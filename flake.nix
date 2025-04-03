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

  outputs = { self, nixpkgs, deploy-rs, ... }:
    let
      
      # Import utils
 system = "x86_64-linux";
                  pkgs = import nixpkgs { inherit system; };

            common = import ./utils/common.nix;
            
    in {
      # NixOS configurations for each host
 nixosConfigurations = {
        haproxy = nixpkgs.lib.nixosSystem {
          inherit system pkgs common;
          modules = [ ./hosts/haproxy ];
        };

        technitium = nixpkgs.lib.nixosSystem {
          inherit system pkgs common;
          modules = [ ./hosts/technitium ];
        };
      };
      
      # Deployment configuration using deploy-rs
      deploy.nodes = {
        haproxy = {
          hostname = "hl-lxc-haproxy.local";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.haproxy;
          };
        };
        
        technitium = {
          hostname = "hl-lxc-technitium.local";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.technitium;
          };
        };
        
      };
      
      # Check deployments
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
