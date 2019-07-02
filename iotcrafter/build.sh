#!/bin/bash -e

# Should be called from image-builder directory => ./iotcrafter/build.sh

echo "Started: $(date)"

time=$(date +%Y-%m-%d)
DIR="$PWD"

if [ -f config ]; then
	source config
fi
if [ -z "${IMG_CONF}" ]; then
    echo "IMG_CONF not set" 1>&2
    exit 1
fi
if [ -z "${IMG_NAME}" ]; then
    echo "IMG_NAME not set" 1>&2
    exit 1
fi

# Setup chroot hooks

cat > "${DIR}/chroot_before_hook" <<-__EOF__
. ${DIR}/iotcrafter/restore_capemgr_service.sh
. ${DIR}/iotcrafter/install_iotc_version.sh
rm -f ${DIR}/chroot_before_hook
__EOF__

cat > "${DIR}/chroot_after_hook" <<-__EOF__
. ${DIR}/iotcrafter/setup_kernel_modules.sh
rm -f ${DIR}/chroot_after_hook
__EOF__

#scripts/igcw.sh main-patch

#export IMG_NAME
# IMG_CONF is name of config, e.g. iotcrafter-debian-jessie-v4.4
./RootStock-NG.sh -c ${IMG_CONF}

#scripts/igcw.sh main-restore

# Rootfs is ready
echo "Rootfs Done: $(date)"

# Build image

debian_iotcrafter=$(cat ./latest_version)
archive="xz -z -8 -v"
# we don't enable cape-universal
beaglebone="--dtb beaglebone --bbb-old-bootloader-in-emmc --hostname beaglebone"

# TODO consider (rcn-ee_bb.org-stable.sh):
#beaglebone="--dtb beaglebone --rootfs_label rootfs --hostname beaglebone \
#--enable-uboot-cape-overlays --enable-uboot-pru-rproc-44ti"

# TODO: allow different image types for the same config (IMG_CONF)
# need revising pack-error-cleanup-try loop (postbuild.sh)

# Publish options for original images (IOT images)
# publish/rcn-ee_seeed-stable.sh
#beaglebone="--dtb beaglebone --bbb-old-bootloader-in-emmc \
#--rootfs_label rootfs --hostname beaglebone --enable-cape-universal"
# publish/bb.org_4gb_stable.sh
#beaglebone="--dtb beaglebone --bbb-old-bootloader-in-emmc \
#--rootfs_label rootfs --hostname beaglebone --enable-cape-universal"
# publish/rcn-ee_bb.org-stable.sh
#beaglebone="--dtb beaglebone --rootfs_label rootfs --hostname beaglebone --enable-uboot-cape-overlays"
# + pru_rproc_v44ti="--enable-uboot-pru-rproc-44ti"

cat > ${DIR}/deploy/gift_wrap_final_images.sh <<-__EOF__
#!/bin/bash -e

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
            sed -i 's/^cmdline=.*\$/& init=\/opt\/iotc\/bin\/iotc_init.sh/
                    s/^dtb=/#dtb=/
                    s/^#*enable_uboot_overlays=[0-1]/enable_uboot_overlays=0/' \${TEMPDIR}/disk/boot/uEnv.txt
            echo "/boot/uEnv.txt: init script defined, no override for default DTB ensured"

            #sed -i '/^loadall=/ifixfdt=echo IoTC: check \${fdtbase}..; if test \${fdtbase} = am335x-boneblack; then setenv fdtbase am335x-boneblack-emmc-overlay; setenv fdtfile am335x-boneblack-emmc-overlay.dtb; fi; if test \${fdtbase} = am335x-boneblack-wireless; then setenv fdtbase am335x-boneblack-wireless-emmc-overlay; setenv fdtfile am335x-boneblack-wireless-emmc-overlay.dtb; fi;' \${TEMPDIR}/disk/uEnv.txt
            #sed -i 's/^\(loadall=.*\)run loadxrd; run loadxfdt;\(.*\)$/\1run loadxrd; run fixfdt; run loadxfdt;\2/' \${TEMPDIR}/disk/uEnv.txt
            #echo "/uEnv.txt: DTB substitution defined"
        ;;
    esac
__EOF__

#cd ${DIR}/deploy
#./gift_wrap_final_images.sh
#cd ${DIR}

echo "Build done: $(date)"
echo "deploy/gift_wrap_final_images.sh ready to make the final image"
