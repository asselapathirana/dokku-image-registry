# dokku-image-registry

Automated provisioning of a Docker image registry running on a Dokku host.

## Prerequisites

- Dokku installed and working on the remote server.
- Passwordless SSH access from your machine to the Dokku host.
- If you use a non-root SSH user, it must have passwordless `sudo` for Dokku and for writing under `/var/lib/dokku/data/storage`.
- DNS for your registry domain pointing at the Dokku server (if using a custom domain).

## Usage

From this directory:

```bash
export DOKKU_HOST="root@example.com"           # or user@example.com (must be a normal OS user, not 'dokku')
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

## Testing with GitHub Actions

This repo includes a simple GitHub Actions workflow that builds and pushes a
tiny test image to your Dokku registry.

### Configure GitHub secrets

In your GitHub repository settings, define these secrets:

- `DOKKU_REGISTRY_URL` – e.g. `registry.example.com`
- `DOKKU_REGISTRY_USERNAME` – same value you used for `REGISTRY_USERNAME`
- `DOKKU_REGISTRY_PASSWORD` – same value you used for `REGISTRY_PASSWORD`

Ensure your registry is reachable from the public internet (or from GitHub’s
runners) and uses a valid TLS certificate (e.g. via `ENABLE_LETSENCRYPT=1`).

### Run the workflow

- Go to “Actions” in GitHub, select “Push test image to Dokku registry”.
- Use “Run workflow” to trigger it.

If it succeeds, you should see `dokkuregistry-test:latest` in your registry:

- `docker pull registry.example.com/dokkuregistry-test:latest`

## Local testing script

You can also test your registry from your local machine with a helper script:

```bash
export REGISTRY_DOMAIN="registry.example.com"
export REGISTRY_USERNAME="registry"
export REGISTRY_PASSWORD="change-me"

./test-registry-local.sh
```

The script logs in to your registry over HTTPS, pushes a small `alpine:3.20`
image as `dokkuregistry-local-test:latest`, and then pulls it back to confirm
everything works end-to-end.
