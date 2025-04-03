{
    description = "Technitium DNS Server LXC Container";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        bento.url = "github:rapenne-s/bento";
        bento.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs = { self, nixpkgs, bento, ... }:
        let
            system = "x86_64-linux";
            pkgs = nixpkgs.legacyPackages.${system};
            lib = nixpkgs.lib;

            bentoNodes = {
                technitium = {
                    nixosModules = [
                        bento.nixosModules.bento
                        ./configuration.nix
                    ];
                    hostName = "technitium.local"; # Update with your actual LXC hostname or IP
                    sshOpts = [ "-p" "22" "-i" "/path/to/your/private/key" ];
                };
            };

        in {
            # Expose as a bento network for deployment
            bento = bento.lib.${system}.makeBentoNetworkFromNodes bentoNodes;

            # Expose as NixOS configuration for local testing
            nixosConfigurations.technitium = lib.nixosSystem {
                inherit system;
                modules = [
                    bento.nixosModules.bento
                    ./configuration.nix
                ];
            };
        };
}
