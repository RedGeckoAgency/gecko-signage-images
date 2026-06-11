#!/bin/bash -e

echo "[99-gecko] Installing Gecko payload into /opt/gecko and enabling gecko-bootstrap.service"

echo "Current directory: $(pwd)"
ls -la files/opt/gecko || echo "files/opt/gecko missing!"

cat > "${ROOTFS_DIR}/etc/gecko-image-stage99.txt" <<EOF
stage=99-gecko
purpose=install /opt/gecko + first-boot bootstrap unit
date=$(date)
EOF
chmod 644 "${ROOTFS_DIR}/etc/gecko-image-stage99.txt"

install -d "${ROOTFS_DIR}/opt"
install -d "${ROOTFS_DIR}/opt/gecko"

cp -rv "files/opt/gecko/." "${ROOTFS_DIR}/opt/gecko/"

# ── Write VERSION file ──
# build-local.sh writes the VERSION into files/opt/gecko/ from the correct git
# context (host, outside Docker) so it arrives here via the cp -rv above.
# Only fall back to git if the file is missing or empty.
if [ -s "${ROOTFS_DIR}/opt/gecko/VERSION" ]; then
  echo "[99-gecko] VERSION: $(cat "${ROOTFS_DIR}/opt/gecko/VERSION") (from staging area)"
else
  # Secondary fallback: try git from the Docker-visible path.
  # NOTE: $0 inside Docker resolves to /pi-gen/…, so ../../ points to pi-gen root
  # which has no version tags. This will usually produce an empty string, but we
  # guard against that explicitly.
  _FALLBACK_VER=$(git -C "$(dirname "$0")/../.." describe --tags --abbrev=0 2>/dev/null || true)
  _FALLBACK_VER=$(echo "$_FALLBACK_VER" | sed 's/^v//')
  if [ -n "$_FALLBACK_VER" ]; then
    echo "$_FALLBACK_VER" > "${ROOTFS_DIR}/opt/gecko/VERSION"
    echo "[99-gecko] VERSION: $_FALLBACK_VER (from git fallback)"
  else
    echo "[99-gecko] WARNING: VERSION could not be determined; agent will report 'dev'"
  fi
fi

if [ -f "${ROOTFS_DIR}/opt/gecko/tools/bootstrap_gecko.sh" ]; then
  sed -i 's/\r$//' "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
  chmod +x "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
fi

install -D -m 0755 "files/usr/local/sbin/gecko-bootstrap-once"       "${ROOTFS_DIR}/usr/local/sbin/gecko-bootstrap-once"

install -D -m 0644 "files/etc/systemd/system/gecko-bootstrap.service"       "${ROOTFS_DIR}/etc/systemd/system/gecko-bootstrap.service"
install -d "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf ../gecko-bootstrap.service "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/gecko-bootstrap.service"

# ── APT Repository Config ──
echo "[99-gecko] Configuring Gecko APT repository..."
install -d "${ROOTFS_DIR}/etc/apt/sources.list.d"
install -d "${ROOTFS_DIR}/etc/apt/apt.conf.d"
install -d "${ROOTFS_DIR}/usr/share/keyrings"

# 1. GPG Public Key (for package verification)
# Always pipe through gpg --dearmor: works for both ASCII-armored and binary input.
# APT requires a binary (non-armored) keyring at /usr/share/keyrings/*.gpg
if [ -f "files/usr/share/keyrings/gecko-repo.gpg" ]; then
  gpg --dearmor < "files/usr/share/keyrings/gecko-repo.gpg" \
    > "${ROOTFS_DIR}/usr/share/keyrings/gecko-repo.gpg"
  chmod 0644 "${ROOTFS_DIR}/usr/share/keyrings/gecko-repo.gpg"
else
  echo "WARNING: files/usr/share/keyrings/gecko-repo.gpg missing! APT repo will fail signature checks."
fi

# 2. APT Source List
cat > "${ROOTFS_DIR}/etc/apt/sources.list.d/gecko.list" <<'EOF'
deb [signed-by=/usr/share/keyrings/gecko-repo.gpg] https://d3a03e0wzyqfqi.cloudfront.net stable main
EOF
chmod 644 "${ROOTFS_DIR}/etc/apt/sources.list.d/gecko.list"

# 3. APT Basic Auth credentials (standard APT auth.conf format)
# APT sends these as HTTP Basic Auth, which the Lambda@Edge validates.
if [ -f "files/etc/apt/auth.conf.d/gecko.conf" ]; then
  mkdir -p "${ROOTFS_DIR}/etc/apt/auth.conf.d"
  install -m 0600 "files/etc/apt/auth.conf.d/gecko.conf" "${ROOTFS_DIR}/etc/apt/auth.conf.d/"
else
  echo "WARNING: files/etc/apt/auth.conf.d/gecko.conf missing! APT repo will return 403."
  mkdir -p "${ROOTFS_DIR}/etc/apt/auth.conf.d"
  echo "machine d3a03e0wzyqfqi.cloudfront.net login token password DUMMY_TOKEN" \
    > "${ROOTFS_DIR}/etc/apt/auth.conf.d/gecko.conf"
  chmod 600 "${ROOTFS_DIR}/etc/apt/auth.conf.d/gecko.conf"
fi
# Remove old header-based auth file if it exists
rm -f "${ROOTFS_DIR}/etc/apt/apt.conf.d/99-gecko-auth"


on_chroot << 'EOF'
apt-get update
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip \
  git rsync ca-certificates curl \
  xserver-xorg xinit openbox x11-xserver-utils xserver-xorg-legacy dbus-x11 \
  unclutter fonts-dejavu fonts-liberation \
  libgles2-mesa libgl1-mesa-dri \
  chromium-browser || apt-get install -y --no-install-recommends chromium

systemctl enable gecko-bootstrap.service

systemctl set-default multi-user.target || true
systemctl disable lightdm.service 2>/dev/null || true
systemctl disable gdm.service gdm3.service 2>/dev/null || true
systemctl disable sddm.service 2>/dev/null || true
systemctl disable greetd.service 2>/dev/null || true
systemctl disable userconfig.service 2>/dev/null || true
systemctl disable userconf.service userconf-pi.service 2>/dev/null || true
systemctl disable piwiz.service 2>/dev/null || true

rm -f /etc/xdg/autostart/piwiz.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/gnome-initial-setup.desktop 2>/dev/null || true

# Set default WLAN Country to US to avoid WPA3/connection issues
raspi-config nonint do_wifi_country US
EOF

# ── Pre-create Python venv and install dependencies (offline-ready first boot) ──
echo "[99-gecko] Pre-baking Python venv into image..."
on_chroot << 'EOF'
python3 -m venv /opt/gecko/.venv
/opt/gecko/.venv/bin/pip install --upgrade pip wheel
/opt/gecko/.venv/bin/pip install --no-cache-dir -r /opt/gecko/requirements.txt
EOF

install -D -m 0644 /dev/stdin "${ROOTFS_DIR}/etc/ssh/sshd_config.d/99-gecko.conf" <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
CONF

on_chroot << 'EOF'
systemctl enable ssh || true
EOF
