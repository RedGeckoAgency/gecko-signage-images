#!/bin/bash
set -euo pipefail
# ──────────────────────────────────────────────────────────────
#  build-deb.sh — Build a .deb package for gecko-agent
#
#  Usage:
#    ./scripts/build-deb.sh --version <X.Y.Z> [--arch armhf|arm64] [--out <dir>]
#
#  Outputs: out/deb/gecko-agent_<version>-1_<arch>.deb
# ──────────────────────────────────────────────────────────────
cd "$(dirname "$0")/.."

ARCH="armhf"
OUT_DIR="out/deb"
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)    ARCH="$2"; shift 2 ;;
        --out)     OUT_DIR="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        *)         echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "ERROR: --version is required (e.g. --version 1.3.0)" >&2
    exit 1
fi

GECKO_SRC="gecko"
if [ ! -d "$GECKO_SRC" ]; then
    echo "ERROR: gecko/ source directory not found." >&2
    exit 1
fi

DEB_VERSION="${VERSION}-1"
PKG_NAME="gecko-agent_${DEB_VERSION}_${ARCH}"
echo "Building: ${PKG_NAME}.deb (v${VERSION})"

# ── Create package tree ──
STAGE=$(mktemp -d)
trap "rm -rf $STAGE" EXIT

PKG_ROOT="$STAGE/$PKG_NAME"
mkdir -p "$PKG_ROOT/DEBIAN"
mkdir -p "$PKG_ROOT/opt/gecko"
mkdir -p "$PKG_ROOT/etc/systemd/system"

# ── Copy DEBIAN control files ──
sed "s/{{VERSION}}/${DEB_VERSION}/g" packaging/DEBIAN/control.template > "$PKG_ROOT/DEBIAN/control"
# Set architecture
sed -i "s/^Architecture:.*/Architecture: ${ARCH}/" "$PKG_ROOT/DEBIAN/control"
cp packaging/DEBIAN/postinst "$PKG_ROOT/DEBIAN/postinst"
cp packaging/DEBIAN/prerm "$PKG_ROOT/DEBIAN/prerm"
cp packaging/DEBIAN/conffiles "$PKG_ROOT/DEBIAN/conffiles"
chmod 755 "$PKG_ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/prerm"

# ── Copy agent source code ──
# Top-level files
for f in agent_main.py app.py browser_launcher.py wifi_manager.py requirements.txt; do
    [ -f "$GECKO_SRC/$f" ] && cp "$GECKO_SRC/$f" "$PKG_ROOT/opt/gecko/"
done

# Directories (agent_core, tools, static, templates)
for d in agent_core tools static templates; do
    [ -d "$GECKO_SRC/$d" ] && cp -r "$GECKO_SRC/$d" "$PKG_ROOT/opt/gecko/"
done

# ── Clean unwanted files ──
find "$PKG_ROOT/opt/gecko" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$PKG_ROOT/opt/gecko" -name "*.pyc" -delete 2>/dev/null || true
rm -rf "$PKG_ROOT/opt/gecko/tests" 2>/dev/null || true

# ── Copy systemd service & bake version into Environment= ──
if [ -f "$GECKO_SRC/systemd/gecko-agent.service" ]; then
    UNIT_DST="$PKG_ROOT/etc/systemd/system/gecko-agent.service"
    cp "$GECKO_SRC/systemd/gecko-agent.service" "$UNIT_DST"
    # Insert Environment=GECKO_AGENT_VERSION=<X> right after [Service]
    sed -i "/^\[Service\]/a Environment=GECKO_AGENT_VERSION=${VERSION}" "$UNIT_DST"
fi

# ── Write build manifest ──
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
cat > "$PKG_ROOT/opt/gecko/.deb-manifest" <<EOF
version=${VERSION}
deb_version=${DEB_VERSION}
arch=${ARCH}
built=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
git_sha=${GIT_SHA}
EOF

# ── Build .deb ──
mkdir -p "$OUT_DIR"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$OUT_DIR/${PKG_NAME}.deb"

# ── Checksums ──
DEB_PATH="$OUT_DIR/${PKG_NAME}.deb"
HASH=$(sha256sum "$DEB_PATH" | cut -d' ' -f1)
echo "$HASH  ${PKG_NAME}.deb" > "$OUT_DIR/${PKG_NAME}.sha256"

SIZE=$(du -h "$DEB_PATH" | cut -f1)

echo ""
echo "──────────────────────────────────────────────"
echo "  .deb Package Built Successfully"
echo "──────────────────────────────────────────────"
echo "  Version:  ${VERSION}"
echo "  Arch:     ${ARCH}"
echo "  Package:  ${DEB_PATH}"
echo "  SHA-256:  ${HASH}"
echo "  Size:     ${SIZE}"
echo "──────────────────────────────────────────────"
