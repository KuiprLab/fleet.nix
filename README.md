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

## Getting Started

TODO
