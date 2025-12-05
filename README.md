# dokku-image-registry

Automated provisioning of a Docker image registry running on a Dokku host.

## Prerequisites

- Dokku installed and working on the remote server.
- Passwordless SSH access from your machine to the Dokku host.
- DNS for your registry domain pointing at the Dokku server (if using a custom domain).

## Usage

From this directory:

```bash
export DOKKU_HOST="dokku@example.com"          # or user@example.com
export REGISTRY_APP="registry"                 # optional
export REGISTRY_DOMAIN="registry.example.com"  # optional
export REGISTRY_USERNAME="registry"            # optional
export REGISTRY_PASSWORD="change-me"           # recommended
export ENABLE_LETSENCRYPT="1"                  # optional

./deploy-registry.sh
```

The script is idempotent: you can re-run it to converge the remote Dokku host
to the desired registry configuration without manual commands.

Registry image data is stored persistently on the Dokku host under:

- `/var/lib/dokku/data/storage/<REGISTRY_APP>/data`

This directory is mounted into the registry container at `/var/lib/registry`,
so images survive container restarts and redeploys.
