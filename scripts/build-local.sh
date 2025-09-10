#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends         git rsync xz-utils bmap-tools qemu-user-static pigz >/dev/null || true
fi

git submodule update --init --recursive

WORKDIR="$(pwd)"
OUTDIR="$WORKDIR/out"
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

PIGEN_COMMIT="master"
rm -rf "$WORKDIR/.cache/pi-gen"

git clone --depth 1 --branch "$PIGEN_COMMIT" https://github.com/RPi-Distro/pi-gen.git "$WORKDIR/.cache/pi-gen"
if [ -f "$WORKDIR/gecko/image/config" ]; then
  echo "[build] using private config from gecko/image/config"
  rsync -a "$WORKDIR/gecko/image/config" "$WORKDIR/.cache/pi-gen/config"
else
  echo "[build] using public template config"
  rsync -a "$WORKDIR/config" "$WORKDIR/.cache/pi-gen/config"
fi
rsync -a "$WORKDIR/stages/" "$WORKDIR/.cache/pi-gen/stage3/"

if [ ! -d "$WORKDIR/gecko" ]; then
  echo "ERROR: expected ./gecko folder (submodule or copied)."
  exit 1
fi
mkdir -p "$WORKDIR/.cache/pi-gen/stage3/99-gecko/files/opt"
rsync -a "$WORKDIR/gecko/" "$WORKDIR/.cache/pi-gen/stage3/99-gecko/files/opt/gecko/"

if [ -f "$WORKDIR/.cache/pi-gen/stage3/99-gecko/files/opt/gecko/tools/bootstrap_gecko.sh" ]; then
  chmod +x "$WORKDIR/.cache/pi-gen/stage3/99-gecko/files/opt/gecko/tools/bootstrap_gecko.sh"
fi

pushd "$WORKDIR/.cache/pi-gen" >/dev/null
sudo ./build-docker.sh
popd >/dev/null

rsync -a "$WORKDIR/.cache/pi-gen/deploy/" "$OUTDIR/"
(cd "$OUTDIR" && sha256sum * > SHA256SUMS || shasum -a 256 * > SHA256SUMS || true)

echo
echo "Build complete. Artifacts in: $OUTDIR"
ls -lh "$OUTDIR"
