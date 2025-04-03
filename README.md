# LXC NixOS Fleet

A multi-flake project for deploying NixOS to LXC containers using Bento. Each container has its own independent flake for maximum flexibility and modularity.

## Directory Structure

```
 .
├──  hosts
│   ├──  haproxy
│   │   ├──  configuration.nix
│   │   ├──  flake.nix
│   │   └──  haproxy.cfg
│   └──  technitium
│       ├──  configuration.nix
│       └──  flake.nix
├── 󰂺 README.md
└──  utils
├──  bento.nix
├──  common.nix
└──  fleet.nix
```

## Getting Started

1. You need at least one main machine where bento will be running on and serving its files. This machine is valled `hl-lxc-bento-master` in my case.
2. Install NixOS onto it by following https://nixos.wiki/wiki/Proxmox_Linux_Container.
3. Clone the repo onto the master.
4. Run `nixos-rebuild switch --flake .` to deploy the flake. Make sure the hostname is correct, or specify a configuration by running `nixos-rebuild switch --flake .#hl-lxc-bento-master`.

