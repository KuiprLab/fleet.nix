{
    description = "NixOS configurations for homelab LXC containers";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

        # For automatic deployments
        deploy-rs = {
            url = "github:serokell/deploy-rs";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        # For flake updates
        flake-utils.url = "github:numtide/flake-utils";

        # For system hardening
        nixos-hardened = {
            url = "github:nixos/nixos-hardware";
        };
    };

    outputs = { self, nixpkgs, deploy-rs, flake-utils, nixos-hardened, ... }:
        let
            # System types to support
            supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

            # Helper function to generate an attribute set by system
            forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

            # Import utils
            utils = import ./utils/common.nix { inherit nixpkgs; };

            # Common configuration for all hosts
            commonConfiguration = { config, pkgs, ... }: {
                imports = [
                    # Add common modules here
                ];

                # Enable flakes and auto-update
                nix = {
                    package = pkgs.nixVersions.stable;
                    extraOptions = ''
            experimental-features = nix-command flakes
            auto-optimise-store = true
                    '';
                    gc = {
                        automatic = true;
                        dates = "weekly";
                        options = "--delete-older-than 30d";
                    };
                    settings = {
                        auto-optimise-store = true;
                        allowed-users = [ "@wheel" ];
                        trusted-users = [ "root" "@wheel" ];
                    };
                };

                # Auto-update system from Git
                system.autoUpgrade = {
                    enable = true;
                    flake = "github:KuiprLab/fleet.nix.git";  # Replace with your actual repo
                    dates = "04:00";
                    randomizedDelaySec = "45min";
                    allowReboot = true;
                    rebootWindow = {
                        lower = "01:00";
                        upper = "05:00";
                    };
                };
            };
        in {
            # NixOS configurations for each host
            nixosConfigurations = {

                haproxy = nixpkgs.lib.nixosSystem {
                    system = "x86_64-linux";
                    modules = [
                        ./hosts/haproxy/configuration.nix
                        commonConfiguration
                    ];
                    specialArgs = { 
                        inherit utils nixos-hardened;
                    };
                };

                technitium = nixpkgs.lib.nixosSystem {
                    system = "x86_64-linux";
                    modules = [
                        ./hosts/technitium/configuration.nix
                        commonConfiguration
                    ];
                    specialArgs = { 
                        inherit utils nixos-hardened;
                    };
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
                    hostname = "technitium.local";
                    profiles.system = {
                        user = "root";
                        path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.technitium;
                    };
                };

            };

            # Development shell for working with this repository
            devShells = forAllSystems (system:
                let pkgs = nixpkgs.legacyPackages.${system};
                in {
                    default = pkgs.mkShell {
                        buildInputs = with pkgs; [
                            nixos-rebuild
                            deploy-rs.packages.${system}.deploy-rs
                            git
                        ];
                    };
                }
            );

            # Check deployments
            checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
        };
}
