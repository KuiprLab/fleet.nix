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

TODO

# Automated NixOS Deployments

This system enables automatic configuration updates for NixOS hosts whenever changes are pushed to the GitHub repository.

## How It Works

1. **GitHub Webhook Service**: Each NixOS host runs a webhook listener service that responds to GitHub push events.

2. **Scheduled Checks**: Hosts will periodically check for updates (every 30 minutes by default).

3. **GitHub Actions**: When you push to the main branch, GitHub Actions will trigger webhooks on all hosts.



