
# the same setup as for jessie
# TODO: consider switch to u-boot overlays
case "${deb_codename}" in
	stretch|buster)
		sudo cp "${OIB_DIR}/target/init_scripts/systemd-capemgr.service" "${tempdir}/lib/systemd/system/capemgr.service"
		sudo chown root:root "${tempdir}/lib/systemd/system/capemgr.service"
		sudo cp "${OIB_DIR}/target/init_scripts/capemgr" "${tempdir}/etc/default/"
		sudo chown root:root "${tempdir}/etc/default/capemgr"
		;;
esac

