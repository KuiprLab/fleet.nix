{
    description = "HAProxy Reverse Proxy LXC Container";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        bento.url = "github:rapodaca/bento";
        bento.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs = { self, nixpkgs, bento, ... }:
        let
            system = "x86_64-linux";
            pkgs = nixpkgs.legacyPackages.${system};
            lib = nixpkgs.lib;

            bentoNodes = {
                haproxy = {
                    nixosModules = [
                        bento.nixosModules.bento
                        ./configuration.nix
                    ];
                    hostName = "haproxy.local"; # Update with your actual LXC hostname or IP
                    sshOpts = [ "-p" "22" "-i" "/path/to/your/private/key" ];
                };
            };

        in {
            # Expose as a bento network for deployment
            bento = bento.lib.${system}.makeBentoNetworkFromNodes bentoNodes;

            # Expose as NixOS configuration for local testing
            nixosConfigurations.haproxy = lib.nixosSystem {
                inherit system;
                modules = [
                    bento.nixosModules.bento
                    ./configuration.nix
                ];
            };
        };
}
