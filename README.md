# fleet.nix — GitOps for Proxmox + NixOS

This repository contains a Nix flake to manage NixOS and Darwin configurations and helper scripts to deploy them to Proxmox LXC containers. It also includes tooling to create and register GitHub self-hosted runners.

Overview

- `scripts/deploy.sh` — Consolidated deployment script (interactive and CI modes, and LXC creation).
- `scripts/deploy-lxc.sh` — Backwards-compatible wrapper that calls `deploy.sh create-lxc`.
- `scripts/create-github-runner.sh` — Creates a Proxmox LXC (or uses an existing one) and installs a GitHub Actions self-hosted runner.
- `.github/workflows/deploy.yml` — Workflow that runs on pushes to `main` and executes the `ci` deploy on a `self-hosted` runner.

Prerequisites

- A GitHub repository (this repo) with appropriate permissions.
- A Proxmox host with API/CLI access from the runner (or run the runner on the Proxmox host directly).
- Nix installed on the runner host (recommended for deployment operations).
- SSH access to the Proxmox host and to created containers (for creation and runner setup).

Usage

Local Interactive Deploy

- Run `./scripts/deploy.sh local`
- Select a `nixosConfiguration` from the flake using `fzf`.

CI / Non-interactive Deploy

- On a self-hosted runner (Linux), pushing to `main` will trigger `.github/workflows/deploy.yml` which runs `./scripts/deploy.sh ci`.
- Ensure the self-hosted runner has the following installed: `nix`, `jq`, `git`, and network access to your Proxmox host if you plan to create LXC containers.

Create an LXC (manual)

- Example: `./scripts/deploy.sh create-lxc -h proxmox.local -i 101 -n haproxy -p 10.0.0.10 -c haproxy`
- The script will create an LXC using the latest NixOS template and push `./hosts/<config>/configuration.nix` if provided.

Create and Register a GitHub Runner

1. Generate a registration token in your GitHub repo or org (Settings → Actions → Runners → New self-hosted runner → Generate token).
2. Run the script with required args:
   ./scripts/create-github-runner.sh --proxmox-host proxmox.local --id 120 --name runner01 --ip 10.0.0.20 --github-url https://github.com/OWNER/REPO --token <REGISTRATION_TOKEN>

The script will:

- Optionally create the LXC (unless `--skip-create` is passed).
- Wait for SSH on the container.
- Download the latest `actions/runner` release and configure it using the provided token.

Notes on Security

- Keep your GitHub registration token secret and short-lived.
- For production use, create a dedicated GitHub Actions runner user and harden access.

Troubleshooting

- If the workflow does not run on your server, ensure the runner is online and labeled `self-hosted` and `linux`.
- Check runner logs in the container (`/home/actions/actions-runner/_diag`) for errors.
- If SSH times out during runner creation, ensure the container has network and SSH enabled.

Contributing

- Open a PR with small, focused changes. Describe the changes and include testing steps.

License

- This repository follows the license indicated in the upstream project (if any). Check repository root for license information.
