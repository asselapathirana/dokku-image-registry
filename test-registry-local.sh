#!/usr/bin/env bash

set -euo pipefail

if [[ "${DEBUG:-}" == "1" ]]; then
  set -x
fi

usage() {
  cat <<EOF
Usage:
  REGISTRY_DOMAIN=registry.example.com \\
  REGISTRY_USERNAME=registry \\
  REGISTRY_PASSWORD=change-me \\
  ./test-registry-local.sh

Assumes:
  - The registry is reachable at https://\$REGISTRY_DOMAIN
  - You have Docker installed and running locally
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REGISTRY_DOMAIN="${REGISTRY_DOMAIN:-registry.srv.pathirana.net}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-registry}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"

if [[ -z "${REGISTRY_DOMAIN}" || -z "${REGISTRY_USERNAME}" || -z "${REGISTRY_PASSWORD}" ]]; then
  echo "REGISTRY_DOMAIN, REGISTRY_USERNAME and REGISTRY_PASSWORD must be set." >&2
  usage
  exit 1
fi

IMAGE_NAME="dokkuregistry-local-test"
IMAGE_TAG="latest"
REMOTE_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "==> Logging in to ${REGISTRY_DOMAIN}..."
echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_DOMAIN}" --username "${REGISTRY_USERNAME}" --password-stdin

echo "==> Pulling base image (alpine:3.20)..."
docker pull alpine:3.20 >/dev/null

echo "==> Tagging test image as ${REMOTE_IMAGE}..."
docker tag alpine:3.20 "${REMOTE_IMAGE}"

echo "==> Pushing ${REMOTE_IMAGE}..."
docker push "${REMOTE_IMAGE}"

echo "==> Pulling ${REMOTE_IMAGE} back to verify..."
docker pull "${REMOTE_IMAGE}"

echo "==> Success: test image pushed and pulled from ${REGISTRY_DOMAIN}."

