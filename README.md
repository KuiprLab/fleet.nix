# LXC NixOS Fleet
[![Nix Configuration Validation](https://github.com/KuiprLab/fleet.nix/actions/workflows/validate.yaml/badge.svg)](https://github.com/KuiprLab/fleet.nix/actions/workflows/validate.yaml)

NixOS flake configurations for my LXC containers. Easily deploy new containers and configurations using bash scripts.

## Directory Structure

```
.
├── flake.lock
├── flake.nix
├── hosts
│   ├── bind
│   │   └── configuration.nix
│   └── haproxy
│       ├── configuration.nix
│       └── haproxy.cfg
├── README.md
├── renovate.json
├── scripts
│   ├── configuration.nix
│   ├── deploy-lxc.sh
│   └── deploy.sh
└── utils
├── authorizedKeys
├── auto-update.nix
└── common.nix
```

# Getting Started

## Prerequisites

- A Proxmox Host
- The NixOS LXC template downloaded (see: https://nixos.wiki/wiki/Proxmox_Linux_Container)

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
`root` is the default username for LXCs in Proxmox
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
4. Edit your configuration.nix
    - It is important that you add the following snippet to your `configuration.nix` in order for nix to recognise it as a lxc container:
    ```nix
    imports = [
        (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ];
    proxmoxLXC = {
        manageNetwork = false;
        privileged = false;
    };
    ```
5. Run `./scripts/deploy-lxc.sh` to create a new LXC
6. Run `./scripts/deploy.sh` to deploy your node
