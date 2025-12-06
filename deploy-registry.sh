#!/usr/bin/env bash

set -euo pipefail

if [[ "${DEBUG:-}" == "1" ]]; then
  set -x
fi

usage() {
  cat <<EOF
Usage: DOKKU_HOST=<host> ./deploy-registry.sh [options]

Required environment variables:
  DOKKU_HOST          SSH host (e.g. root@example.com or user@example.com)

Optional environment variables:
  DOKKU_USER          SSH user if not embedded in DOKKU_HOST (default: derived from DOKKU_HOST or root)
  REGISTRY_APP        Dokku app name for the registry (default: registry)
  REGISTRY_DOMAIN     Virtual host/domain for the registry (default: registry.\$DOKKU_HOST without user)
  REGISTRY_USERNAME   HTTP auth username (default: registry)
  REGISTRY_PASSWORD   HTTP auth password (required if using auth)

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
  default_user="root"
  default_host="${DOKKU_HOST}"
fi

DOKKU_USER="${DOKKU_USER:-$default_user}"
BARE_HOST="${default_host}"
REGISTRY_APP="${REGISTRY_APP:-registry}"
REGISTRY_DOMAIN="${REGISTRY_DOMAIN:-registry.${BARE_HOST}}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-registry}"

if [[ -z "${REGISTRY_PASSWORD:-}" ]]; then
  echo "Error: REGISTRY_PASSWORD is not set." >&2
  echo "       Please set REGISTRY_PASSWORD to a strong value before running this script." >&2
  exit 1
fi

ssh_target="${DOKKU_USER}@${BARE_HOST}"

if [[ "${DOKKU_USER}" == "dokku" ]]; then
  echo "Error: This script must run over SSH as a normal OS user (e.g. root), not the special dokku SSH user." >&2
  echo "       Set DOKKU_HOST to something like 'root@your-server' so shell commands (mkdir, openssl, etc.) can run." >&2
  exit 1
fi

if [[ "${DOKKU_USER}" == "root" ]]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

remote() {
  ssh -o StrictHostKeyChecking=no "${ssh_target}" "$@"
}

echo "==> Using Dokku host: ${ssh_target}"
echo "==> Registry app: ${REGISTRY_APP}"
echo "==> Registry domain: ${REGISTRY_DOMAIN}"

echo "==> Ensuring dokku is available on remote host..."
remote "command -v dokku >/dev/null 2>&1"

echo "==> Ensuring 'htpasswd' is available on remote host..."
remote "${SUDO_CMD} bash -lc 'command -v htpasswd >/dev/null 2>&1 || { echo \"Error: htpasswd not found. Please install apache2-utils on the Dokku host.\" >&2; exit 1; }'"

echo "==> Creating registry app if missing..."
if ! remote "${SUDO_CMD} dokku apps:exists ${REGISTRY_APP}"; then
  remote "${SUDO_CMD} dokku apps:create ${REGISTRY_APP}"
fi

echo "==> Ensuring persistent storage for registry data..."
remote "${SUDO_CMD} mkdir -p /var/lib/dokku/data/storage/${REGISTRY_APP}/data"
remote "${SUDO_CMD} dokku storage:mount ${REGISTRY_APP} /var/lib/dokku/data/storage/${REGISTRY_APP}/data:/var/lib/registry || true"

echo "==> Setting registry Docker image (registry:2)..."
remote "${SUDO_CMD} dokku git:from-image ${REGISTRY_APP} registry:2 || true"

echo "==> Configuring environment variables..."
remote "${SUDO_CMD} dokku config:set --no-restart ${REGISTRY_APP} REGISTRY_STORAGE_DELETE_ENABLED=true REGISTRY_HTTP_ADDR=0.0.0.0:5000"

if [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
  echo "==> Enabling HTTP basic auth for registry..."
  remote "${SUDO_CMD} dokku config:set --no-restart ${REGISTRY_APP} REGISTRY_AUTH=htpasswd REGISTRY_AUTH_HTPASSWD_REALM='Registry Realm' REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd"

  echo "==> Creating auth directory and htpasswd file..."
  remote "${SUDO_CMD} mkdir -p /var/lib/dokku/data/storage/${REGISTRY_APP}/auth"
  remote "${SUDO_CMD} htpasswd -Bbc /var/lib/dokku/data/storage/${REGISTRY_APP}/auth/htpasswd '${REGISTRY_USERNAME}' '${REGISTRY_PASSWORD}'"
  remote "${SUDO_CMD} dokku storage:mount ${REGISTRY_APP} /var/lib/dokku/data/storage/${REGISTRY_APP}/auth:/auth || true"
fi

echo "==> Setting domain..."
remote "${SUDO_CMD} dokku domains:set ${REGISTRY_APP} ${REGISTRY_DOMAIN}"

echo "==> Configuring proxy ports (HTTP 80 -> 5000)..."
remote "${SUDO_CMD} dokku ports:add ${REGISTRY_APP} http:80:5000 || true"
remote "${SUDO_CMD} dokku nginx:set ${REGISTRY_APP} client-max-body-size 0"
remote "${SUDO_CMD} dokku nginx:validate-config ${REGISTRY_APP} --clean"

echo "==> Restarting app..."
remote "${SUDO_CMD} dokku ps:restart ${REGISTRY_APP}"

echo "==> Done."
echo
echo "You can now push images using (example):"
echo "  docker login ${REGISTRY_DOMAIN}"
echo "  docker tag myimage:latest ${REGISTRY_DOMAIN}/myimage:latest"
echo "  docker push ${REGISTRY_DOMAIN}/myimage:latest"
echo
echo "To enable HTTPS with Let's Encrypt once HTTP is working, run:"
echo "  ssh dokku@${BARE_HOST} letsencrypt:enable ${REGISTRY_APP}"
