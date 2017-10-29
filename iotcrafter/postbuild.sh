#!/bin/bash

# Run from container working dir, i.e. from image-builder/
DIR="$PWD"
BUILD_RC=$1
echo "Running Iotcrafter postbuild.sh script in ${DIR}, prev step rc=${BUILD_RC}"

cleanup_mapping()
{
	loop_dev=$(losetup |grep  "${DIR}.*\.img" |cut -f 1 -d " ")
	[ "${loop_dev}" = "" ] && echo "nothing  to cleanup" && return

	# assume .img is setup up once
	loop_base=$(basename ${loop_dev})
	mounts=$(mount | grep "${loop_base}*" | cut -f3 -d " " | sort -r)
	echo "loop_dev=${loop_dev}"
	echo "loop mounts: '$mounts'"

	sync
	for mdev in $mounts; do
		umount $mdev
	done

	sync
	kpartx -d $loop_dev
	losetup -d $loop_dev
}

if [ "${BUILD_RC}" = "0" ]; then
	# wrap final image, try a number of times
	cd ${DIR}/deploy

	try=3
	while [ $try -gt 0 ]; do
		try=$((try - 1))
		./gift_wrap_final_images.sh
		BUILD_RC=$?
		cleanup_mapping
		[ "${BUILD_RC}" = "0" ] && break
	done

	cd ${DIR}
fi

echo ${BUILD_RC} > iotcrafter/build_rc

# restore parent's ownership to the dirs: deploy
chown -R --reference=. deploy
