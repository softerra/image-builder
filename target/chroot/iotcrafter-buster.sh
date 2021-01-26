#!/bin/sh -e
#
# Copyright (c) 2014-2020 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

u_boot_release="v2019.04"
u_boot_release_x15="v2020.10-rc2"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

image_type_mod=${image_type#iotcrafter}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			echo "Patching: /etc/profile"
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	echo "" >> /etc/securetty
	echo "#USB Gadget Serial Port" >> /etc/securetty
	echo "ttyGS0" >> /etc/securetty

#	#make the sound card work by default
#	if [ -f /etc/alsa/tlv320aic3104.state.txt ] ; then
#		if [ -d /var/lib/alsa/ ] ; then
#			cp -v /etc/alsa/tlv320aic3104.state.txt /var/lib/alsa/asound.state
#			cp -v /etc/alsa/tlv320aic3104.conf.txt /etc/asound.conf
#		fi
#	fi
}

setup_desktop () {
	if [ -d /etc/X11/ ] ; then
		wfile="/etc/X11/xorg.conf"
		echo "Patching: ${wfile}"
		echo "Section \"Monitor\"" > ${wfile}
		echo "        Identifier      \"Builtin Default Monitor\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Device\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Device 0\"" >> ${wfile}
		echo "        Driver          \"fbdev\"" >> ${wfile}
		echo "#HWcursor_false        Option          \"HWcursor\"          \"false\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Screen\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "        Device          \"Builtin Default fbdev Device 0\"" >> ${wfile}
		echo "        Monitor         \"Builtin Default Monitor\"" >> ${wfile}
		echo "#DefaultDepth        DefaultDepth    16" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"ServerLayout\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default Layout\"" >> ${wfile}
		echo "        Screen          \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
	fi

	wfile="/etc/lightdm/lightdm.conf"
	if [ -f ${wfile} ] ; then
		echo "Patching: ${wfile}"
		sed -i -e 's:#autologin-user=:autologin-user='$rfs_username':g' ${wfile}
		sed -i -e 's:#autologin-session=:autologin-session='$rfs_default_desktop':g' ${wfile}
		if [ -f /opt/scripts/3rdparty/xinput_calibrator_pointercal.sh ] ; then
			sed -i -e 's:#display-setup-script=:display-setup-script=/opt/scripts/3rdparty/xinput_calibrator_pointercal.sh:g' ${wfile}
		fi
	fi

	if [ ! "x${rfs_desktop_background}" = "x" ] ; then
		mkdir -p /home/${rfs_username}/.config/ || true
		if [ -d /opt/scripts/desktop-defaults/buster/lxqt/ ] ; then
			cp -rv /opt/scripts/desktop-defaults/buster/lxqt/* /home/${rfs_username}/.config
		fi
		chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}/.config/
	fi

	#Disable dpms mode and screen blanking
	#Better fix for missing cursor
	wfile="/home/${rfs_username}/.xsessionrc"
	echo "#!/bin/sh" > ${wfile}
	echo "" >> ${wfile}
	echo "xset -dpms" >> ${wfile}
	echo "xset s off" >> ${wfile}
	echo "xsetroot -cursor_name left_ptr" >> ${wfile}
	chown -R ${rfs_username}:${rfs_username} ${wfile}
}

install_git_repos () {
	if [ -f /usr/bin/make ] ; then
		echo "Installing pip packages"
		git_repo="https://github.com/adafruit/adafruit-beaglebone-io-python.git"
		git_target_dir="/opt/source/adafruit-beaglebone-io-python"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			sed -i -e 's:4.1.0:3.4.0:g' setup.py || true
			if [ -f /usr/bin/python3 ] ; then
				python3 setup.py install || true
			fi
			git reset HEAD --hard || true
		fi
	fi

	if [ -d /usr/local/lib/node_modules/bonescript ] ; then
		if [ -d /etc/apache2/ ] ; then
			#bone101 takes over port 80, so shove apache/etc to 8080:
			if [ -f /etc/apache2/ports.conf ] ; then
				sed -i -e 's:80:8080:g' /etc/apache2/ports.conf
			fi
			if [ -f /etc/apache2/sites-enabled/000-default ] ; then
				sed -i -e 's:80:8080:g' /etc/apache2/sites-enabled/000-default
			fi
			if [ -f /etc/apache2/sites-enabled/000-default.conf ] ; then
				sed -i -e 's:80:8080:g' /etc/apache2/sites-enabled/000-default.conf
			fi
			if [ -f /var/www/html/index.html ] ; then
				rm -rf /var/www/html/index.html || true
			fi
		fi
	fi

	if [ -f /var/www/html/index.nginx-debian.html ] ; then
		rm -rf /var/www/html/index.nginx-debian.html || true

		if [ -d /opt/scripts/distro/buster/nginx/ ] ; then
			cp -v /opt/scripts/distro/buster/nginx/default /etc/nginx/sites-available/default
		fi
	fi

	git_repo="https://github.com/strahlex/BBIOConfig.git"
	git_target_dir="/opt/source/BBIOConfig"
	git_clone

	#am335x-pru-package
	if [ -f /usr/include/prussdrv.h ] ; then
		git_repo="https://github.com/biocode3D/prufh.git"
		git_target_dir="/opt/source/prufh"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			if [ -f /usr/bin/make ] ; then
				make LIBDIR_APP_LOADER=/usr/lib/ INCDIR_APP_LOADER=/usr/include
			fi
			cd /
		fi
	fi

	git_repo="https://github.com/beagleboard/BeagleBoard-DeviceTrees"
	git_target_dir="/opt/source/dtb-4.14-ti"
	git_branch="v4.14.x-ti"
	git_clone_branch

	git_repo="https://github.com/beagleboard/BeagleBoard-DeviceTrees"
	git_target_dir="/opt/source/dtb-4.19-ti"
	git_branch="v4.19.x-ti-overlays"
	git_clone_branch

	git_repo="https://github.com/beagleboard/BeagleBoard-DeviceTrees"
	git_target_dir="/opt/source/dtb-5.4-ti"
	git_branch="v5.4.x-ti-overlays"
	git_clone_branch

	git_repo="https://github.com/beagleboard/bb.org-overlays"
	git_target_dir="/opt/source/bb.org-overlays"
	git_clone

	if [ -f /usr/lib/librobotcontrol.so ] ; then
		git_repo="https://github.com/StrawsonDesign/librobotcontrol"
		git_target_dir="/opt/source/librobotcontrol"
		git_clone

		git_repo="https://github.com/mcdeoliveira/rcpy"
		git_target_dir="/opt/source/rcpy"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			if [ -f /usr/bin/python3 ] ; then
				/usr/bin/python3 setup.py install
			fi
		fi

		git_repo="https://github.com/mcdeoliveira/pyctrl"
		git_target_dir="/opt/source/pyctrl"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			if [ -f /usr/bin/python3 ] ; then
				/usr/bin/python3 setup.py install
			fi
		fi
	fi

	git_repo="https://github.com/mvduin/py-uio"
	git_target_dir="/opt/source/py-uio"
	git_clone
}

other_source_links () {
	rcn_https="https://rcn-ee.com/repos/git/u-boot-patches"

	mkdir -p /opt/source/u-boot_${u_boot_release}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-omap3_beagle-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0002-U-Boot-BeagleBone-Cape-Manager.patch
	mkdir -p /opt/source/u-boot_${u_boot_release_x15}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release_x15}/" ${rcn_https}/${u_boot_release_x15}/0001-am57xx_evm-fixes.patch
	rm /home/${rfs_username}/.wget-hsts || true

	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt
	echo "u-boot_${u_boot_release_x15} : /opt/source/u-boot_${u_boot_release_x15}" >> /opt/source/list.txt

	chown -R ${rfs_username}:${rfs_username} /opt/source/
}

unsecure_root () {
#	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
#	sed -i -e 's:'$root_password'::g' /etc/shadow

#	if [ -f /etc/ssh/sshd_config ] ; then
#		#Make ssh root@beaglebone work..
#		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
#		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
#		#Starting with Jessie:
#		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
#	fi

	if [ -d /etc/sudoers.d/ ] ; then
		#Don't require password for sudo access
		echo "${rfs_username} ALL=NOPASSWD: ALL" >/etc/sudoers.d/${rfs_username}
		chmod 0440 /etc/sudoers.d/${rfs_username}
	fi
}

is_this_qemu

setup_system
setup_desktop

if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
	chown ${rfs_username}:${rfs_username} /home/${rfs_username}/.gitconfig
fi
other_source_links
#unsecure_root
#

## disable connman, use ifup instead
## the rest is assumed to be configured by iotc_init.sh script at first start
#systemctl disable connman
## disable SoftAp (if enabled, connmand is started for the first time when running
## /usr/bin/bb-wl18xx-tether which restarts it
#sed -i 's/^\(TETHER_ENABLED\)=.*$/\1=no/' /etc/default/bb-wl18xx

#systemctl disable apache2

# back apt-daily* stuff
systemctl enable apt-daily.service
systemctl enable apt-daily.timer
systemctl enable apt-daily-upgrade.service
systemctl enable apt-daily-upgrade.timer

# change default target from graphical to multi-user
systemctl set-default multi-user.target

# install it here when almost whole system is set up (debian user exists)
npm config set unsafe-perm true
npm install yarn -g
npm i npm@latest -g

# add own repo
cat > /etc/apt/sources.list.d/iotcrafter.list <<EOF
deb [arch=all,armhf] http://download.iotcrafter.com/iotc/bbb buster main
EOF
# add repo key
wget -qO - http://download.iotcrafter.com/iotc/iotcrafter.gpg.key | apt-key add -

apt-get -y update

echo iotc iotc/cpuid string BBB | debconf-set-selections
echo iotc iotc/kernvers string ${repo_rcnee_pkg_version} | debconf-set-selections
echo iotc iotc/load-overlays boolean false | debconf-set-selections
echo iotc iotc/uboot-overlays boolean true | debconf-set-selections

apt-get -y install iotc-core iotc-ide
dpkg-reconfigure -fnoninteractive -plow unattended-upgrades

# remove all iotc's settings
echo PURGE | debconf-communicate iotc

# fix supervisor start order
sed -i 's/^After=\(.*\)$/After=\1 getty.target/' /lib/systemd/system/supervisor.service

IOTC_INIT_REV=22b0a544b139aff5574c6801e796914eb7241c54
wget -P /opt/iotc/bin/ https://raw.githubusercontent.com/softerra/iotc_scripts/${IOTC_INIT_REV}/board/iotc_init.sh
sed -i 's/^\(iotc_init_version\)=.*$/\1="'${IOTC_INIT_REV}'"/' /opt/iotc/bin/iotc_init.sh
chmod 755 /opt/iotc/bin/iotc_init.sh
# set iotc_init options
# - don't force ifup for wlan
sed -i 's/^\(IOTC_WLAN_FORCE_IFUP\)=.*$/\1=0/' /opt/iotc/bin/iotc_init.sh

# Hold packages (#7502)
apt-mark hold linux-image-${repo_rcnee_pkg_version}

chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}
