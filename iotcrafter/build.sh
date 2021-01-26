#!/bin/bash -e

# Should be called from image-builder directory => ./iotcrafter/build.sh

echo "Started: $(date)"

time=$(date +%Y-%m-%d)
DIR="$PWD"

# a proxy can be used
# export apt_proxy=proxy.gfnd.rcn-ee.org:3142/

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
archive="xz -T0 -z -8 -v"
# we don't enable cape-universal
beaglebone="--dtb beaglebone --rootfs_label rootfs --hostname beaglebone --enable-uboot-cape-overlays --enable-uboot-disable-video --enable-uboot-disable-audio"
pru_rproc=""
if [[ "${IMG_CONF}" =~ v4\.14 ]]; then
	pru_rproc="--enable-uboot-pru-rproc-414ti"
elif [[ "${IMG_CONF}" =~ v4\.19 ]]; then
	pru_rproc="--enable-uboot-pru-rproc-419ti"
elif [[ "${IMG_CONF}" =~ v5\.4 ]]; then
	pru_rproc="--enable-uboot-pru-rproc-54ti"
fi


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
                if [ -f \${base_rootfs}.tar ] ; then
                        tar xf \${base_rootfs}.tar
                fi
        fi
}

archive_img () {
        if [ -f \${wfile}.img ] ; then
                #prevent xz warning for 'Cannot set the file group: Operation not permitted'
                sudo chown 1000:1000 \${wfile}.img
                if [ ! -f \${wfile}.bmap ] ; then
                        if [ -f /usr/bin/bmaptool ] ; then
                                bmaptool create -o \${wfile}.bmap \${wfile}.img
                        fi
                fi
                ${archive} \${wfile}.img && sha256sum \${wfile}.img.xz > \${wfile}.img.xz.sha256sum &
        fi
}

generate_img () {
        if [ ! "x\${base_rootfs}" = "x" ] ; then
                if [ -d \${base_rootfs}/ ] ; then
                        cp -f setup_sdcard_*_hook \${base_rootfs}/ || true
                        cd \${base_rootfs}/

                        # force final tar for rootfs to log into a file in the directory
                        #sed -i 's/^[[:space:]]*tar.*--verbose.*\$/& >> setup_sdcard_tar.log/' ./setup_sdcard.sh
                        sudo ./setup_sdcard.sh \${options}

                        mv *.img ../ || true
                        mv *.job.txt ../ || true
                        cp image-builder.project ../ || true
                        cd ..
                fi
        fi
}

base_rootfs="${debian_iotcrafter}"
options="--img-4gb \${base_rootfs} ${beaglebone} ${pru_rproc}"
generate_img

exit 0
__EOF__

chmod +x ${DIR}/deploy/gift_wrap_final_images.sh

cat > ${DIR}/deploy/setup_sdcard_populate_after_hook <<-__EOF__
    echo "setup_sdcard_populate_after_hook: func stack: \${FUNCNAME[*]}"
    case "\${FUNCNAME[1]}" in
        populate_rootfs)
            # Perform the same uEnv.txt editing as iotc-core's debian/postinst
            # iotc-core could not do this because uEnv.txt is not ready at the stage of the package installation

            # comment everything
            # skip these: s/^uboot_overlay_pru=/#&/
            sed -i 's/^uboot_overlay_addr[0-9]*=/#&/
                    s/^dtb_overlay=/#&/
                    s/^disable_uboot_overlay_/#&/
                    s/^enable_uboot_cape_universal=/#&/
                    s/^disable_uboot_overlay_addr[0-9]*=/#&/
                   ' \${TEMPDIR}/disk/boot/uEnv.txt
            # enable iotc overlays and othe roptions
            # skip these: s/^#disable_uboot_overlay_emmc=.*$/disable_uboot_overlay_emmc=1/
            sed -i 's/^#uboot_overlay_addr4=.*$/uboot_overlay_addr4=\/lib\/firmware\/BB-PWM-00A0.dtbo/
                    s/^#uboot_overlay_addr5=.*$/uboot_overlay_addr5=\/lib\/firmware\/BB-W1-P8.19-00A0.dtbo/
                    s/^#disable_uboot_overlay_video=.*$/disable_uboot_overlay_video=1/
                    s/^#disable_uboot_overlay_audio=.*$/disable_uboot_overlay_audio=1/
                   ' \${TEMPDIR}/disk/boot/uEnv.txt

            # embed iotc_init.sh one time initialization
            sed -i 's/^cmdline=.*\$/& init=\/opt\/iotc\/bin\/iotc_init.sh/
                   ' \${TEMPDIR}/disk/boot/uEnv.txt
            echo "/boot/uEnv.txt: init script defined, iotc overlays preset"
        ;;
    esac
__EOF__

#cd ${DIR}/deploy
#./gift_wrap_final_images.sh
#cd ${DIR}

echo "Build done: $(date)"
echo "deploy/gift_wrap_final_images.sh ready to make the final image"
