#!/bin/bash
set -euo pipefail

# Usage: ./build-iso.sh [variant]
#
# Builds an Anaconda installer ISO for KineticOS.
# Variants: default (AMD/Intel), nvidia (NVIDIA open driver) and
# nvidia-legacy (NVIDIA proprietary driver, older GPUs).
# Local only — lands in ./output/ and stays there.
#
# Set LOCAL=1 to use a locally-built image instead of pulling from registry.

VARIANT="${1:-${VARIANT:-default}}"
# The registry tag matches the variant unless TAG is overridden.
TAG="${TAG:-$VARIANT}"

IMAGE_NAME="${IMAGE_NAME:-kineticos}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
REGISTRY="${REGISTRY:-ghcr.io/theblack-don}"
# bootc-image-builder needs the target root filesystem when the source image
# does not declare one. The kickstart installs to btrfs, so default to that.
ROOTFS="${ROOTFS:-btrfs}"

cd "$(dirname "$0")"

# The kickstart points the installed system at the matching registry tag, so
# each variant uses its own config and output name:
#   default        -> kineticos-<date>.iso          (iso-kineticos.toml)
#   nvidia         -> kineticos-nvidia-<date>.iso   (iso-kineticos-nvidia.toml)
#   nvidia-legacy  -> kineticos-nvidia-legacy-<date>.iso
if [[ "$VARIANT" == "default" ]]; then
  VARIANT_CONFIG="$(pwd)/disk_config/iso-kineticos.toml"
  ISO_STEM="kineticos"
else
  VARIANT_CONFIG="$(pwd)/disk_config/iso-kineticos-${VARIANT}.toml"
  ISO_STEM="kineticos-${VARIANT}"
fi
CONFIG="${CONFIG:-$VARIANT_CONFIG}"
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
  --rootfs "$ROOTFS" \
  --use-librepo=True \
  "localhost/${IMAGE_NAME}:${TAG}"

sudo chown -R "$USER:$(id -gn)" output/

DATE="$(date +%Y%m%d)"
FINAL="output/${ISO_STEM}-${DATE}.iso"
mv -f "output/bootiso/install.iso" "$FINAL"
rm -rf output/bootiso output/qcow2 output/manifest-*.json

echo "ISO: $(pwd)/${FINAL}"
