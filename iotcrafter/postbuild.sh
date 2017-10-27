#!/bin/bash

# Run from container working dir, i.e. from image-builder/

BUILD_RC=$1
echo ${BUILD_RC} > iotcrafter/build_rc

echo "Running Iotcrafter postbuild.sh script in $(pwd)"
#if [ -f config ]; then
#	source config
#fi

# restore parent's ownership to the dirs: deploy
chown -R --reference=. deploy

#echo "IOTCRAFTER_KERNEL_DIR=${IOTCRAFTER_KERNEL_DIR}"
#if [ -n "${IOTCRAFTER_KERNEL_DIR}" ]; then
#	chown -R --reference=. ${IOTCRAFTER_KERNEL_DIR}
#fi

devs=$(ls /dev/mapper/loop*)
mounts=$(mount | grep loop | cut -f1 -d " ")
echo "loop devs: '$devs'"
echo "loop mounts: '$mounts'"
if [ "$mounts" != "" ]; then
	for mdev in $mounts; do
		umount $mdev
	done
fi
if [ "$devs" != "" ]; then
	for dev in $devs; do
		kpartx -d $dev
	done
fi
