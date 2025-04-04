# LXC NixOS Fleet

A multi-flake project for deploying NixOS to LXC containers using Bento. Each container has its own independent flake for maximum flexibility and modularity.

## Directory Structure

```
 .
├──  flake.lock
├──  flake.nix
├──  hosts
│   ├──  haproxy
│   │   ├──  configuration.nix
│   │   └──  haproxy.cfg
│   └──  technitium
│       └──  configuration.nix
├── 󰂺 README.md
├── 󰉼 renovate.json
├──  scripts
│   ├──  deploy-lxc.sh
│   └──  deploy.sh
└──  utils
└──  common.nix
```

# Getting Started

## Deploying an existing config

1. Run `./scripts/deploy-lxc.sh` to create a new lxc. The script will:
    - Create a new lxc container with the given parameters
    - Load a basic configuration.nix onto it and activate it
    - This enables ssh without a password!
2. When the LXC has been created run `./scripts/deploy.sh`
    - Select the host you want to deploy to
    - deploy-rs will automatically build and activate the correct flake

## Adding a New Host

1. Create a new folder inside `hosts/` with the name of your host and a `configuration.nix` file
2. Inside the flake add the following inside `nixosConfigurations`:
```nix
<hostname> = nixpkgs.lib.nixosSystem {
    inherit system pkgs;
    specialArgs = {inherit self;};
    modules =
        commonModules
        ++ [
            ./hosts/<hostname>/configuration.nix
        ];
};
```
3. Create a new node configuration inside `deploy.nodes` in your flake:
```nix
<hostname> = {
    hostname = "<hostname-or-ip>";
    profiles.system = {
        user = "root";
        sshUser = "root";
        path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.<hostname>;
    };
};
```
`root` is the default username for LXCs in Proxmox
4. Edit your configuration.nix
5. Run `./scripts/deploy-lxc.sh` to create a new LXC
6. Run `./scripts/deploy.sh` to deploy your node
