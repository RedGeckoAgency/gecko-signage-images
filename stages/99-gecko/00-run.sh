#!/bin/bash -e

echo "[99-gecko] Installing Gecko payload into /opt/gecko and enabling gecko-bootstrap.service"

install -d "${ROOTFS_DIR}/opt"
install -d "${ROOTFS_DIR}/opt/gecko"
cp -a "files/opt/gecko/." "${ROOTFS_DIR}/opt/gecko/"

if [ -f "${ROOTFS_DIR}/opt/gecko/tools/bootstrap_gecko.sh" ]; then
  sed -i 's/\r$//' "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
  chmod +x "${ROOTFS_DIR}/opt/gecko/tools/"*.sh 2>/dev/null || true
fi

install -D -m 0755 "files/usr/local/sbin/gecko-bootstrap-once"       "${ROOTFS_DIR}/usr/local/sbin/gecko-bootstrap-once"

install -D -m 0644 "files/etc/systemd/system/gecko-bootstrap.service"       "${ROOTFS_DIR}/etc/systemd/system/gecko-bootstrap.service"

on_chroot << 'EOF'
systemctl enable gecko-bootstrap.service

systemctl set-default multi-user.target || true
systemctl disable lightdm.service 2>/dev/null || true
systemctl disable gdm.service gdm3.service 2>/dev/null || true
systemctl disable sddm.service 2>/dev/null || true
systemctl disable greetd.service 2>/dev/null || true
systemctl disable userconfig.service 2>/dev/null || true

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
