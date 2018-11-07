#!/bin/bash

if [ ! -d "$1" ]; then
	echo "Specify root fs path as arg1"
	exit 0
fi
ROOTFS_DIR=$1

on_chroot() {
	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/proc)"; then
		mount -t proc proc "${ROOTFS_DIR}/proc"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/dev)"; then
		mount --bind /dev "${ROOTFS_DIR}/dev"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/dev/pts)"; then
		mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/sys)"; then
		mount --bind /sys "${ROOTFS_DIR}/sys"
	fi

	# share container's /tmp with chroot environment
	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/tmp)"; then
		mount --bind /tmp "${ROOTFS_DIR}/tmp"
	fi

	if [ ! -x "${ROOTFS_DIR}/usr/bin/qemu-arm-static" ]; then
    	cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"
	fi

#	capsh --drop=cap_setfcap "--chroot=${ROOTFS_DIR}/" -- "$@"
	chroot ${ROOTFS_DIR} /bin/bash

	rm -f ${ROOTFS_DIR}/usr/bin/qemu-arm-static

	umount -fl ${ROOTFS_DIR}/tmp
	umount -fl ${ROOTFS_DIR}/sys
	umount -fl ${ROOTFS_DIR}/dev/pts
	umount -fl ${ROOTFS_DIR}/dev
	umount -fl ${ROOTFS_DIR}/proc
}
#export -f on_chroot

on_chroot
