
# global iotc vars start with "iotc_" and defined in project configs
# local iotc vars start with "iotc__"

iotc__old_dir=$(pwd)
iotc__work_dir="${DIR}/ignore/iotc"

##
## Beging
##
mkdir -p ${iotc__work_dir}
cd ${iotc__work_dir}

##
## download kernel headers
##
echo "Downloading linux headers: ${repo_rcnee_pkg_version}"

# setup APT to use local temporary cache and sources list
cat > apt.conf <<EOF
Acquire::AllowInsecureRepositories "true";
Dir::Etc::main ".";
Dir::Etc::Parts "./apt.conf.d";
Dir::Etc::sourcelist "./sources.list";
Dir::Etc::sourceparts "./sources.list.d";
Dir::State "./apt-tmp";
Dir::State::status "./apt-tmp/status";
Dir::Cache "./apt-tmp";
EOF

mkdir -p apt-tmp/lists/partial
touch apt-tmp/status

echo "tempdir=${tempdir}"
# setup sources for the kernel packages
grep rcn-ee ${tempdir}/etc/apt/sources.list > ./sources.list
echo "Using temporary APT sources: "
cat ./sources.list

apt-get -c apt.conf update
apt-get -y --allow-unauthenticated -c apt.conf download linux-headers-${repo_rcnee_pkg_version}

iotc__pkg_file=$(ls linux-headers-${repo_rcnee_pkg_version}*)
echo "Unpacking kernel headers package is: ${iotc__pkg_file}"

dpkg-deb -x ${iotc__pkg_file} .

iotc__kernel_dir=${iotc__work_dir}/usr/src/linux-headers-${repo_rcnee_pkg_version}

##
## Download iotc sources, build and install
##
iotc__src_subdir=iotc-src
mkdir -p ${iotc__src_subdir}

echo "Preparing iotcrafter overlays"
cp -R ${DIR}/target/iotcrafter/overlays ${iotc__src_subdir}/

echo "Building and installing iotcrafter overlays"
${iotc__src_subdir}/overlays/dtc.sh "${iotc__kernel_dir}" "${tempdir}/lib/firmware/"

if [ "$iotc_modules" != "" ]; then

	echo "Downloading iotcrafter modules"
	for m in $iotc_modules; do
		# cleanup
		#rm -rf ${iotc__src_subdir}/$m
		eval "iotc__repo_url=\$iotc_repo_${m}"
		eval "iotc__repo_rev=\$iotc_repo_${m}_REV"
		echo "Checking out $m: ${iotc__repo_url}@${iotc__repo_rev}"
		git clone ${iotc__repo_url} ${iotc__src_subdir}/$m
		if [ "${iotc__repo_rev}" != "" ]; then
			(cd ${iotc__src_subdir}/$m; git checkout ${iotc__repo_rev})
		fi
	done

	echo "Building and installing iotcrafter modules"
	iotc__MAKE_OPTS="-C ${iotc__kernel_dir} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=${tempdir}"
	for m in $iotc_modules; do
		( cd ${iotc__src_subdir}/$m; \
			make $iotc__MAKE_OPTS M=$PWD clean; \
			make -j8 $iotc__MAKE_OPTS M=$PWD modules && \
				make -j8 $iotc__MAKE_OPTS M=$PWD modules_install )
	done

	# depmod on the final system
	sudo chroot "${tempdir}" /bin/bash -c "depmod -A ${repo_rcnee_pkg_version}"

# "$iotc_modules" != ""
else
echo "No iotcrafter modules specified"
fi

##
## Done
##
cd ${iotc__old_dir}
