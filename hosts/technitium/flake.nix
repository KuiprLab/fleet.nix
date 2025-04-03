{
  description = "Technitium DNS server configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    # This is a host-specific flake that can be used independently
    # or as part of the main flake
    nixosConfigurations.technitium = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
