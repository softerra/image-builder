#!/bin/bash -e

# Should be called from image-builder directory => ./iotcrafter/build.sh

echo "Started: $(date)"

time=$(date +%Y-%m-%d)
DIR="$PWD"

if [ -f config ]; then
	source config
fi
if [ -z "${IMG_NAME}" ]; then
    echo "IMG_NAME not set" 1>&2
    exit 1
fi

cat > "${DIR}/chroot_after_hook" <<-__EOF__
# add our overlays
sudo cp -f ${DIR}/target/iotcrafter/dtbo/*.dtbo \${tempdir}/lib/firmware/
# remove self
rm -f ${DIR}/chroot_after_hook
__EOF__

scripts/igcw.sh main-patch

# IMG_NAME is actually name of config, e.g. iotcrafter-debian-jessie-v4.4
./RootStock-NG.sh -c ${IMG_NAME}

scripts/igcw.sh main-restore

# Rootfs is ready
echo "Rootfs Done: $(date)"

# Build image

debian_iotcrafter=$(cat ./latest_version)
archive="xz -z -8 -v"
beaglebone="--dtb beaglebone --bbb-old-bootloader-in-emmc --hostname beaglebone"

cat > ${DIR}/deploy/gift_wrap_final_images.sh <<-__EOF__
#!/bin/bash

archive_base_rootfs () {
        if [ -d ./\${base_rootfs} ] ; then
                rm -rf \${base_rootfs} || true
        fi
        if [ -f \${base_rootfs}.tar ] ; then
                ${archive} \${base_rootfs}.tar && sha256sum \${base_rootfs}.tar.xz > \${base_rootfs}.tar.xz.sha256sum &
        fi
}

extract_base_rootfs () {
        if [ -d ./\${base_rootfs} ] ; then
                rm -rf \${base_rootfs} || true
        fi

        if [ -f \${base_rootfs}.tar.xz ] ; then
                tar xf \${base_rootfs}.tar.xz
        else
                tar xf \${base_rootfs}.tar
        fi
}

archive_img () {
	#prevent xz warning for 'Cannot set the file group: Operation not permitted'
	sudo chown \${UID}:\${GROUPS} \${wfile}.img
        if [ -f \${wfile}.img ] ; then
                if [ ! -f \${wfile}.bmap ] ; then
                        if [ -f /usr/bin/bmaptool ] ; then
                                bmaptool create -o \${wfile}.bmap \${wfile}.img
                        fi
                fi
                ${archive} \${wfile}.img && sha256sum \${wfile}.img.xz > \${wfile}.img.xz.sha256sum &
        fi
}

generate_img () {
        cp -f setup_sdcard_*_hook \${base_rootfs}/
        cd \${base_rootfs}/
        sudo ./setup_sdcard.sh \${options}
        mv *.img ../
        mv *.job.txt ../
        cp image-builder.project ../
        cd ..
}

base_rootfs="${debian_iotcrafter}"
options="--img-4gb \${base_rootfs} ${beaglebone}"
generate_img

exit 0
__EOF__

chmod +x ${DIR}/deploy/gift_wrap_final_images.sh

cat > ${DIR}/deploy/setup_sdcard_populate_after_hook <<-__EOF__
    echo "setup_sdcard_populate_after_hook: func stack: \${FUNCNAME[*]}"
    case "\${FUNCNAME[1]}" in
        populate_rootfs)
            sed -i 's/^cmdline=.*\$/& init=\/opt\/iotc\/bin\/iotc_init.sh/' \${TEMPDIR}/disk/boot/uEnv.txt
            echo "uEnv.txt: init script defined"
        ;;
    esac
__EOF__

cd ${DIR}/deploy
./gift_wrap_final_images.sh
cd ${DIR}

echo "Done: $(date)"
