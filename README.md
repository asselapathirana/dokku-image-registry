# dokku-image-registry

Automated provisioning of a Docker image registry running on a Dokku host.

## Prerequisites

- Dokku installed and working on the remote server.
- Passwordless SSH access from your machine to the Dokku host.
- If you use a non-root SSH user, it must have passwordless `sudo` for Dokku and for writing under `/var/lib/dokku/data/storage`.
- `htpasswd` available on the Dokku host (e.g. via the `apache2-utils` package) for creating bcrypt-based registry credentials.
- DNS for your registry domain pointing at the Dokku server (if using a custom domain).

## Usage

From this directory:

```bash
export DOKKU_HOST="root@example.com"           # or user@example.com (must be a normal OS user, not 'dokku')
export REGISTRY_APP="registry"                 # optional
export REGISTRY_DOMAIN="registry.example.com"  # optional
export REGISTRY_USERNAME="registry"            # optional
export REGISTRY_PASSWORD="change-me"           # required

./deploy-registry.sh
```

The script is idempotent: you can re-run it to converge the remote Dokku host
to the desired registry configuration without manual commands.

Registry image data is stored persistently on the Dokku host under:

- `/var/lib/dokku/data/storage/<REGISTRY_APP>/data`

This directory is mounted into the registry container at `/var/lib/registry`,
so images survive container restarts and redeploys.

After HTTP is working and you can log in and push images, you can enable HTTPS
with Dokku's Let's Encrypt plugin, for example:

```bash
ssh dokku@example.com letsencrypt:enable registry
```

## Using with GitHub Actions

You can build and push images to this registry from GitHub Actions runners.

1. Confirm your registry is reachable from GitHub (public HTTPS with a valid cert).
2. In your repo settings, add secrets:
   - `DOKKU_REGISTRY_URL` (e.g. `registry.example.com`)
   - `DOKKU_REGISTRY_USERNAME`
   - `DOKKU_REGISTRY_PASSWORD`
3. Add a workflow like:

```yaml
name: Build and push to Dokku registry

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    env:
      APP_NAME: your-app
    steps:
      - uses: actions/checkout@v4

      - name: Derive content tag
        run: echo "TAG_MD5=$(git rev-parse HEAD | md5sum | cut -d' ' -f1)" >> $GITHUB_ENV

      - name: Log in to Dokku registry
        uses: docker/login-action@v3
        with:
          registry: ${{ secrets.DOKKU_REGISTRY_URL }}
          username: ${{ secrets.DOKKU_REGISTRY_USERNAME }}
          password: ${{ secrets.DOKKU_REGISTRY_PASSWORD }}

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOKKU_REGISTRY_URL }}/${{ env.APP_NAME }}:latest
            ${{ secrets.DOKKU_REGISTRY_URL }}/${{ env.APP_NAME }}:${{ env.TAG_MD5 }}
```

- Replace `your-app` in `APP_NAME` with your image name.
- The workflow pushes both a stable `latest` tag and a content-derived MD5 tag so deployment tools (e.g. Argo CD) can detect new images deterministically.
- If you use a custom port, include it in `DOKKU_REGISTRY_URL` (e.g. `registry.example.com:5000`).
- For private repos, keep these secrets at the repo level; for org-wide reuse, use org secrets.

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
