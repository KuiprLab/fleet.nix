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

TODO
