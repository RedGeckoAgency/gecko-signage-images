#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Gecko build-local $(date --iso-8601=seconds)"

PIGEN_REF_ARMHF="${PIGEN_REF_ARMHF:-2025-05-13-raspios-bookworm-armhf}"
PIGEN_REF_ARM64="${PIGEN_REF_ARM64:-2025-05-13-raspios-bookworm-arm64}"

ONLY_ARCH="${ONLY_ARCH:-both}"

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends \
    git rsync xz-utils bmap-tools qemu-user-static pigz dos2unix >/dev/null || true
fi

git submodule update --init --recursive

WORKDIR="$(pwd)"
OUTDIR="$WORKDIR/out"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

if [ ! -d "$WORKDIR/gecko" ]; then
  echo "ERROR: expected ./gecko folder (submodule or copied)."
  exit 1
fi

TEMPLATE_CONFIG_DIR="$WORKDIR/config"

ensure_cfg () {
  local file="$1" key="$2" val="$3"
  if grep -q "^[[:space:]]*${key}=" "$file"; then
    sed -i "s|^[[:space:]]*${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

build_one () {
  local REF="$1"
  local ARCHLBL="$2"

  local RUN_OUT="$OUTDIR/$ARCHLBL"
  local CACHE_DIR="$WORKDIR/.cache/pi-gen-$ARCHLBL"
  local CONTAINER_NAME="pigen_work_${ARCHLBL}"

  echo
  echo "=== [$ARCHLBL] Setup pi-gen ($REF) at $CACHE_DIR ==="
  rm -rf "$CACHE_DIR"
  git -c core.autocrlf=false clone --depth=1 https://github.com/RPi-Distro/pi-gen.git "$CACHE_DIR"
  ( cd "$CACHE_DIR" && git fetch --tags --depth=1 && git checkout -B gecko-build "$REF" )
  echo "[$ARCHLBL] pi-gen ref: $(git -C "$CACHE_DIR" describe --tags --always || git -C "$CACHE_DIR" rev-parse --short HEAD)"

  if [ -f "$WORKDIR/gecko/image/config" ]; then
    echo "[$ARCHLBL] Using private config from gecko/image/config"
    cp -a "$WORKDIR/gecko/image/config" "$CACHE_DIR/config"
  elif [ -d "$TEMPLATE_CONFIG_DIR" ]; then
    echo "[$ARCHLBL] Using public template config"
    cp -a "$TEMPLATE_CONFIG_DIR" "$CACHE_DIR/config"
  else
    echo "[$ARCHLBL] Creating minimal config"
    cat > "$CACHE_DIR/config" <<'EOF'
IMG_NAME="gecko-os"
ENABLE_SSH=1
# Desktop build includes stage4:
STAGE_LIST="stage0 stage1 stage2 stage3 stage4"
RELEASE="bookworm"
EOF
  fi

  if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$CACHE_DIR/config" >/dev/null 2>&1 || true
  else
    sed -i 's/\r$//' "$CACHE_DIR/config" || true
  fi

  ensure_cfg "$CACHE_DIR/config" 'RELEASE' '"bookworm"'
  if grep -q '^STAGE_LIST=' "$CACHE_DIR/config"; then
    sed -i 's#^STAGE_LIST=.*#STAGE_LIST="stage0 stage1 stage2 stage3 stage4"#' "$CACHE_DIR/config"
  else
    echo 'STAGE_LIST="stage0 stage1 stage2 stage3 stage4"' >> "$CACHE_DIR/config"
  fi

  ensure_cfg "$CACHE_DIR/config" 'APT_MIRROR' '"https://deb.debian.org/debian"'
  ensure_cfg "$CACHE_DIR/config" 'APT_MIRROR_RASPBIAN' '"https://raspbian.raspberrypi.org/raspbian"'
  ensure_cfg "$CACHE_DIR/config" 'RPI_MIRROR' '"https://archive.raspberrypi.org/debian"'
  ensure_cfg "$CACHE_DIR/config" 'APT_OPTS' '"-o Acquire::Retries=8 -o Acquire::ForceIPv4=true -o Acquire::http::Timeout=45 -o Acquire::https::Timeout=45 --fix-missing"'

  ensure_cfg "$CACHE_DIR/config" 'LOCALE_DEFAULT' '"en_US.UTF-8"'
  ensure_cfg "$CACHE_DIR/config" 'KEYBOARD_LAYOUT' '"us"'
  ensure_cfg "$CACHE_DIR/config" 'KEYBOARD_KEYMAP' '"us"'
  ensure_cfg "$CACHE_DIR/config" 'TIMEZONE_DEFAULT' '"America/New_York"'

  ensure_cfg "$CACHE_DIR/config" 'DEPLOY_COMPRESSION' '"xz"'
  ensure_cfg "$CACHE_DIR/config" 'COMPRESSION_LEVEL' '"6"'

  {
    echo
    echo "# appended by build script"
    echo "IMG_NAME=\"gecko-${REF}\""
  } >> "$CACHE_DIR/config"

  echo "[$ARCHLBL] Effective config:"
  sed -n '1,200p' "$CACHE_DIR/config"

  mkdir -p "$CACHE_DIR/stage3"
  if [ -d "$WORKDIR/stages" ]; then
    cp -a "$WORKDIR/stages/." "$CACHE_DIR/stage3/"
  fi

  if [ -d "$CACHE_DIR/stage3/99-gecko" ]; then
    if command -v dos2unix >/dev/null 2>&1; then
      find "$CACHE_DIR/stage3/99-gecko" -maxdepth 1 -type f -name "*.sh" -print0 | xargs -0 -r dos2unix >/dev/null 2>&1 || true
    else
      find "$CACHE_DIR/stage3/99-gecko" -maxdepth 1 -type f -name "*.sh" -print0 | xargs -0 -r sed -i 's/\r$//' || true
    fi
    find "$CACHE_DIR/stage3/99-gecko" -maxdepth 1 -type f -name "*.sh" -print0 | xargs -0 -r chmod +x || true

    if [ ! -x "$CACHE_DIR/stage3/99-gecko/00-run.sh" ]; then
      echo "ERROR: Injected stage '$CACHE_DIR/stage3/99-gecko/00-run.sh' is not executable; pi-gen will skip it." >&2
      echo "Fix: ensure your checkout preserves execute bits or run build via this script (it will chmod +x)." >&2
      exit 1
    fi
  fi

  mkdir -p "$CACHE_DIR/stage3/99-gecko/files/opt/gecko"
  cp -a "$WORKDIR/gecko/." "$CACHE_DIR/stage3/99-gecko/files/opt/gecko/" || true
  [ -f "$CACHE_DIR/stage3/99-gecko/files/opt/gecko/tools/bootstrap_gecko.sh" ] && \
    chmod +x "$CACHE_DIR/stage3/99-gecko/files/opt/gecko/tools/bootstrap_gecko.sh"

  mkdir -p "$CACHE_DIR/stage0/00-apt-tuning"
  cat > "$CACHE_DIR/stage0/00-apt-tuning/00-run.sh" <<'EOF'
#!/bin/bash -e
echo 'Acquire::Retries "8";' > /etc/apt/apt.conf.d/99-retries
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99-ipv4
echo 'Acquire::http::Timeout "45";' > /etc/apt/apt.conf.d/99-timeouts
echo 'Acquire::https::Timeout "45";' >> /etc/apt/apt.conf.d/99-timeouts
sed -i 's#http://raspbian\.raspberrypi\.com/raspbian#https://raspbian.raspberrypi.org/raspbian#g' /etc/apt/sources.list 2>/dev/null || true
sed -i 's#http://raspbian\.raspberrypi\.org/raspbian#https://raspbian.raspberrypi.org/raspbian#g' /etc/apt/sources.list 2>/dev/null || true
sed -i 's#http://archive\.raspberrypi\.org/debian#https://archive.raspberrypi.org/debian#g' /etc/apt/sources.list.d/raspi.list 2>/dev/null || true
EOF
  chmod +x "$CACHE_DIR/stage0/00-apt-tuning/00-run.sh"
  docker rm -fv "$CONTAINER_NAME" >/dev/null 2>&1 || true
  pushd "$CACHE_DIR" >/dev/null
    mkdir -p stage4/03-bookshelf
    touch stage4/03-bookshelf/SKIP
    FINALISE_SCRIPT="export-image/05-finalise/01-run.sh"
    if [ -f "$FINALISE_SCRIPT" ]; then
      sed -i -E 's#(cp[[:space:]]+"?\$BMAP_FILE"?[[:space:]]+"?\$DEPLOY_DIR/"?)#\1 || true#g' "$FINALISE_SCRIPT" || true
    fi
    SUDO=""
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo"; fi
    echo "=== [$ARCHLBL] Starting pi-gen Docker build (container: $CONTAINER_NAME) ==="

    max_tries="${MAX_RETRIES:-3}"
    try=1
    rc=1
    while [ "$try" -le "$max_tries" ]; do
      echo "[$ARCHLBL] build attempt $try/$max_tries"
      if $SUDO env CONTAINER_NAME="$CONTAINER_NAME" \
         PRESERVE_CONTAINER=1 CONTINUE=1 \
         DEBIAN_FRONTEND=noninteractive \
         bash ./build-docker.sh; then
        rc=0; break
      fi
      echo "[$ARCHLBL] attempt $try failed; sleeping then retrying..."
      try=$((try+1))
      sleep 10
    done
    if [ "$rc" -ne 0 ]; then
      echo "[$ARCHLBL] Build failed after ${max_tries} attempts."
      exit 1
    fi
  popd >/dev/null

  if [ -f "$CACHE_DIR/deploy/build.log" ] || [ -f "$CACHE_DIR/deploy/build-docker.log" ]; then
    if ! (
      ( [ -f "$CACHE_DIR/deploy/build.log" ] && grep -Fq "[99-gecko] Installing Gecko payload" "$CACHE_DIR/deploy/build.log" ) ||
      ( [ -f "$CACHE_DIR/deploy/build-docker.log" ] && grep -Fq "[99-gecko] Installing Gecko payload" "$CACHE_DIR/deploy/build-docker.log" )
    ); then
      echo "ERROR: Build completed but 99-gecko stage marker was not found in deploy logs." >&2
      echo "This usually means the 'stage3/99-gecko' substage did not run." >&2
      echo "Hint: inspect '$CACHE_DIR/deploy/build.log' and '$CACHE_DIR/deploy/build-docker.log'." >&2
      exit 1
    fi
  else
    echo "WARNING: deploy logs not found; cannot verify 99-gecko stage execution." >&2
  fi

  mkdir -p "$RUN_OUT"
  cp -a "$CACHE_DIR/deploy/." "$RUN_OUT/" || true

  (
    cd "$RUN_OUT"
    shopt -s nullglob
    tag_raw="${GITHUB_REF_NAME:-}"
    tag=""
    if [[ "$tag_raw" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      tag="${tag_raw//\//-}"
    fi
    for old in image_*; do
      new="$old"
      new="$(printf '%s' "$new" | sed -E \
        -e 's/^image_[0-9]{4}-[0-9]{2}-[0-9]{2}-/image-/' \
        -e 's/^image-gecko-[0-9]{4}-[0-9]{2}-[0-9]{2}-/image-gecko-/' \
      )"

      if [ -n "$tag" ] && [[ "$new" == image-gecko-* ]] && [[ "$new" != image-gecko-${tag}-* ]]; then
        new="image-gecko-${tag}-${new#image-gecko-}"
      fi

      if [ "$new" != "$old" ]; then
        if [ -e "$new" ]; then
          echo "ERROR: rename collision: '$old' -> '$new' already exists" >&2
          exit 1
        fi
        mv "$old" "$new"
      fi
    done
  )

  (
    cd "$RUN_OUT"
    ls -1 *.img *.img.xz *.zip *.bmap *.info 2>/dev/null | xargs -r sha256sum > SHA256SUMS || true
  )

  echo
  echo "=== [$ARCHLBL] Build complete. Artifacts in: $RUN_OUT ==="
  ls -lh "$RUN_OUT" || true
}

case "$ONLY_ARCH" in
  armhf)
    build_one "$PIGEN_REF_ARMHF" "armhf"
    ;;
  arm64)
    build_one "$PIGEN_REF_ARM64" "arm64"
    ;;
  both|*)
    build_one "$PIGEN_REF_ARMHF" "armhf"
    build_one "$PIGEN_REF_ARM64" "arm64"
    ;;
esac

echo
echo "All done! Final outputs:"
find "$OUTDIR" -maxdepth 2 -type f -printf "%P\t%k KB\n" | sort
