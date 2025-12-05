#!/usr/bin/env bash

set -euo pipefail

if [[ "${DEBUG:-}" == "1" ]]; then
  set -x
fi

usage() {
  cat <<EOF
Usage: DOKKU_HOST=<host> ./deploy-registry.sh [options]

Required environment variables:
  DOKKU_HOST          SSH host (e.g. dokku@example.com or user@example.com)

Optional environment variables:
  DOKKU_USER          SSH user if not embedded in DOKKU_HOST (default: dokku)
  REGISTRY_APP        Dokku app name for the registry (default: registry)
  REGISTRY_DOMAIN     Virtual host/domain for the registry (default: registry.\$DOKKU_HOST without user)
  REGISTRY_USERNAME   HTTP auth username (default: registry)
  REGISTRY_PASSWORD   HTTP auth password (required if using auth)
  ENABLE_LETSENCRYPT  If "1", install and enable dokku-letsencrypt for the app

This script is idempotent: running it multiple times should converge
the remote Dokku host to the same state.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${DOKKU_HOST:-}" ]]; then
  echo "DOKKU_HOST is required (e.g. dokku@example.com)" >&2
  exit 1
fi

# Derive defaults
if [[ "${DOKKU_HOST}" == *@* ]]; then
  default_user="${DOKKU_HOST%@*}"
  default_host="${DOKKU_HOST#*@}"
else
  default_user="dokku"
  default_host="${DOKKU_HOST}"
fi

DOKKU_USER="${DOKKU_USER:-$default_user}"
BARE_HOST="${default_host}"
REGISTRY_APP="${REGISTRY_APP:-registry}"
REGISTRY_DOMAIN="${REGISTRY_DOMAIN:-registry.${BARE_HOST}}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-registry}"
ENABLE_LETSENCRYPT="${ENABLE_LETSENCRYPT:-0}"

if [[ -z "${REGISTRY_PASSWORD:-}" ]]; then
  echo "Warning: REGISTRY_PASSWORD is not set; registry will not have HTTP auth." >&2
fi

ssh_target="${DOKKU_USER}@${BARE_HOST}"

remote() {
  ssh -o StrictHostKeyChecking=no "${ssh_target}" "$@"
}

echo "==> Using Dokku host: ${ssh_target}"
echo "==> Registry app: ${REGISTRY_APP}"
echo "==> Registry domain: ${REGISTRY_DOMAIN}"

echo "==> Ensuring dokku is available on remote host..."
remote 'command -v dokku >/dev/null 2>&1'

echo "==> Creating registry app if missing..."
if ! remote "dokku apps:exists ${REGISTRY_APP}"; then
  remote "dokku apps:create ${REGISTRY_APP}"
fi

echo "==> Ensuring persistent storage for registry data..."
remote "mkdir -p /var/lib/dokku/data/storage/${REGISTRY_APP}/data"
remote "dokku storage:mount ${REGISTRY_APP} /var/lib/dokku/data/storage/${REGISTRY_APP}/data:/var/lib/registry || true"

echo "==> Setting registry Docker image (registry:2)..."
remote "dokku git:from-image ${REGISTRY_APP} registry:2"

echo "==> Configuring environment variables..."
remote "dokku config:set --no-restart ${REGISTRY_APP} REGISTRY_STORAGE_DELETE_ENABLED=true REGISTRY_HTTP_ADDR=0.0.0.0:5000"

if [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
  echo "==> Enabling HTTP basic auth for registry..."
  htpasswd_line="${REGISTRY_USERNAME}:$(openssl passwd -apr1 "${REGISTRY_PASSWORD}")"
  remote "dokku config:set --no-restart ${REGISTRY_APP} REGISTRY_AUTH=htpasswd REGISTRY_AUTH_HTPASSWD_REALM='Registry Realm' REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd"

  echo "==> Creating auth directory and htpasswd file..."
  remote "mkdir -p /var/lib/dokku/data/storage/${REGISTRY_APP}/auth"
  remote "printf '%s\n' '${htpasswd_line}' > /var/lib/dokku/data/storage/${REGISTRY_APP}/auth/htpasswd"
  remote "dokku storage:mount ${REGISTRY_APP} /var/lib/dokku/data/storage/${REGISTRY_APP}/auth:/auth || true"
else
  echo "==> Skipping HTTP auth configuration (no REGISTRY_PASSWORD provided)..."
fi

echo "==> Setting domain..."
remote "dokku domains:set ${REGISTRY_APP} ${REGISTRY_DOMAIN}"

if [[ "${ENABLE_LETSENCRYPT}" == "1" ]]; then
  echo "==> Ensuring dokku-letsencrypt plugin is installed..."
  if ! remote "dokku plugin:list | grep -q letsencrypt"; then
    remote "sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git"
  fi
  echo "==> Enabling Let's Encrypt for ${REGISTRY_APP}..."
  remote "dokku letsencrypt ${REGISTRY_APP}"
  remote "dokku letsencrypt:cron-job --add"
else
  echo "==> Skipping Let's Encrypt (ENABLE_LETSENCRYPT!=1)..."
fi

echo "==> Restarting app..."
remote "dokku ps:restart ${REGISTRY_APP}"

echo "==> Done."
echo
echo "You can now push images using (example):"
echo "  docker login ${REGISTRY_DOMAIN}"
echo "  docker tag myimage:latest ${REGISTRY_DOMAIN}/myimage:latest"
echo "  docker push ${REGISTRY_DOMAIN}/myimage:latest"
