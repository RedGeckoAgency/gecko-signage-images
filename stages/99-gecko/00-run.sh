#!/bin/bash -e
# Stage script executed by pi-gen during stage3 to install Gecko bits

# ROOTFS_DIR is provided by pi-gen
install -d "${ROOTFS_DIR}/opt"
cp -a "files/opt/gecko" "${ROOTFS_DIR}/opt/gecko"

# Ensure bootstrap is executable (if present)
if [ -f "${ROOTFS_DIR}/opt/gecko/tools/bootstrap_gecko.sh" ]; then
  chmod +x "${ROOTFS_DIR}/opt/gecko/tools/bootstrap_gecko.sh"
fi

# Install our once-only bootstrap wrapper and systemd unit
install -D -m 0755 "files/usr/local/sbin/gecko-bootstrap-once"       "${ROOTFS_DIR}/usr/local/sbin/gecko-bootstrap-once"

install -D -m 0644 "files/etc/systemd/system/gecko-bootstrap.service"       "${ROOTFS_DIR}/etc/systemd/system/gecko-bootstrap.service"

on_chroot << 'EOF'
systemctl enable gecko-bootstrap.service
EOF

# Disable SSH password auth (key-only)
install -D -m 0644 /dev/stdin "${ROOTFS_DIR}/etc/ssh/sshd_config.d/99-gecko.conf" <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
CONF

on_chroot << 'EOF'
systemctl enable ssh || true
EOF
