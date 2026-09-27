#!/bin/bash
set -euo pipefail

# Usage: ./build-iso.sh [tag]
#
# Builds an Anaconda installer ISO for KineticOS.
# Local only — lands in ./output/ and stays there.
#
# Set LOCAL=1 to use a locally-built image instead of pulling from registry.

TAG="${1:-${TAG:-latest}}"

IMAGE_NAME="${IMAGE_NAME:-kineticos}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
REGISTRY="${REGISTRY:-ghcr.io/don-foco}"

cd "$(dirname "$0")"
CONFIG="${CONFIG:-$(pwd)/disk_config/iso-kineticos.toml}"
mkdir -p output

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 1
fi

if [[ -n "${LOCAL:-}" ]]; then
  # Verify the image is in rootful storage
  if ! sudo podman image exists "localhost/${IMAGE_NAME}:${TAG}"; then
    echo "LOCAL=1 set but localhost/${IMAGE_NAME}:${TAG} not in rootful podman storage." >&2
    echo "Either build the image into rootful storage, or copy it across:" >&2
    echo "  sudo podman image scp \"\${UID}@localhost::${IMAGE_NAME}:${TAG}\" \\" >&2
    echo "                        \"root@localhost::${IMAGE_NAME}:${TAG}\"" >&2
    exit 1
  fi
else
  echo "Pulling ${REGISTRY}/${IMAGE_NAME}:${TAG} into rootful podman storage..."
  sudo podman pull "${REGISTRY}/${IMAGE_NAME}:${TAG}"
  sudo podman tag "${REGISTRY}/${IMAGE_NAME}:${TAG}" "localhost/${IMAGE_NAME}:${TAG}"
fi

sudo podman run \
  --rm -it \
  --privileged \
  --pull=newer \
  --net=host \
  --security-opt label=type:unconfined_t \
  -v "$(realpath "$CONFIG"):/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BIB_IMAGE" \
  --type anaconda-iso \
  --use-librepo=True \
  "localhost/${IMAGE_NAME}:${TAG}"

sudo chown -R "$USER:$USER" output/

DATE="$(date +%Y%m%d)"
FINAL="output/kineticos-${DATE}.iso"
mv -f "output/bootiso/install.iso" "$FINAL"
rm -rf output/bootiso output/qcow2 output/manifest-*.json

echo "ISO: $(pwd)/${FINAL}"
