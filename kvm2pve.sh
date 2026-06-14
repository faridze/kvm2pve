#!/usr/bin/env bash
# Legacy wrapper for kvm2pve v1.
set -Eeuo pipefail

cat <<'EOF'
kvm2pve.sh is deprecated.

The old virsh blockcopy/pivot workflow has been replaced by the QMP blockdev-backup workflow.

Use the new scripts:

  Source KVM/Virtualizor host:
    ./kvm2pve-src.sh init
    ./kvm2pve-src.sh discover
    ./kvm2pve-src.sh tunnel
    ./kvm2pve-src.sh attach-target
    ./kvm2pve-src.sh bitmap
    ./kvm2pve-src.sh full
    ./kvm2pve-src.sh watch
    ./kvm2pve-src.sh final

  Destination Proxmox host:
    ./kvm2pve-dst.sh init
    ./kvm2pve-dst.sh export
    ./kvm2pve-dst.sh close
    ./kvm2pve-dst.sh boot

Config:
  cp examples/kvm2pve.env.example kvm2pve.env
EOF

exit 1
