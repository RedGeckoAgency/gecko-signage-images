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

# ── Write VERSION file from git tag ──
IMAGE_VERSION=$(git -C "$(dirname "$0")/../.." describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
echo "${IMAGE_VERSION}" > "${ROOTFS_DIR}/opt/gecko/VERSION"
echo "[99-gecko] Wrote VERSION file: ${IMAGE_VERSION}"

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
if [ -f "files/usr/share/keyrings/gecko-repo.gpg" ]; then
  install -m 0644 "files/usr/share/keyrings/gecko-repo.gpg" "${ROOTFS_DIR}/usr/share/keyrings/"
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

install -D -m 0644 /dev/stdin "${ROOTFS_DIR}/etc/ssh/sshd_config.d/99-gecko.conf" <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
CONF

on_chroot << 'EOF'
systemctl enable ssh || true
EOF
