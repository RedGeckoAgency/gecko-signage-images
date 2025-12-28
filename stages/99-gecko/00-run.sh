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

if [ -f "${ROOTFS_DIR}/opt/gecko/tools/bootstrap_gecko.sh" ]; then
  sed -i 's/\r$//' "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
  chmod +x "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
fi

install -D -m 0755 "files/usr/local/sbin/gecko-bootstrap-once"       "${ROOTFS_DIR}/usr/local/sbin/gecko-bootstrap-once"

install -D -m 0644 "files/etc/systemd/system/gecko-bootstrap.service"       "${ROOTFS_DIR}/etc/systemd/system/gecko-bootstrap.service"
install -d "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf ../gecko-bootstrap.service "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/gecko-bootstrap.service"

on_chroot << 'EOF'
apt-get update
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip \
  git rsync ca-certificates curl \
  xserver-xorg xinit openbox x11-xserver-utils xserver-xorg-legacy dbus-x11 \
  unclutter fonts-dejavu \
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
