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

## Setup Instructions

### 1. Update Repository URL

Edit `utils/auto-update.nix` and replace:
```nix
${pkgs.git}/bin/git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git /etc/nixos
```
with your actual repository URL.

### 2. Configure Webhook Secret

Edit `utils/webhook-service.nix` and replace `your-github-webhook-secret` with a secure secret string.
Update the same secret in `.github/workflows/deploy.yml`.

### 3. Ensure Hosts Have Internet Access

Each host needs to be able to:
- Access your GitHub repository
- Receive incoming webhook requests (for direct triggering)

### 4. Initial Deployment

For the first-time setup, use deploy-rs to push the initial configuration:

```bash
nix run github:serokell/deploy-rs .#haproxy
nix run github:serokell/deploy-rs .#technitium
```

### 5. Add GitHub Webhook (optional)

For additional reliability, set up a webhook in your GitHub repository settings:
- Webhook URL: `http://your-host-ip:9000/hooks/nixos-update`
- Content type: `application/json`
- Secret: Your chosen webhook secret
- Events: Just the `push` event

## Troubleshooting

### Checking Webhook Logs

```bash
ssh root@your-host "cat /var/log/github-webhook.log"
```

### Manual Update

If you need to trigger an update manually:

```bash
ssh root@your-host "cd /etc/nixos && git pull && nixos-rebuild switch --flake .#$(hostname)"
```

### Security Considerations

- The webhook service runs as root to allow system reconfiguration
- A secret is used to authenticate webhook requests
- Consider using HTTPS for the webhook if exposing it to the internet
