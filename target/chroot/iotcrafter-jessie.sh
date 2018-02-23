#!/bin/sh -e
#
# Copyright (c) 2014-2016 Robert Nelson <robertcnelson@gmail.com>
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

u_boot_release="v2017.09"
u_boot_release_x15="ti-2017.01"

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
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
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

#		echo "        Driver          \"modesetting\"" >> ${wfile}
#		echo "        Option          \"AccelMethod\"   \"none\"" >> ${wfile}
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
		sed -i -e 's:#autologin-session=UNIMPLEMENTED:autologin-session='$rfs_default_desktop':g' ${wfile}
		if [ -f /opt/scripts/3rdparty/xinput_calibrator_pointercal.sh ] ; then
			sed -i -e 's:#display-setup-script=:display-setup-script=/opt/scripts/3rdparty/xinput_calibrator_pointercal.sh:g' ${wfile}
		fi
	fi

	if [ ! "x${rfs_desktop_background}" = "x" ] ; then
		mkdir -p /home/${rfs_username}/.config/ || true
		if [ -d /opt/scripts/desktop-defaults/jessie/lxqt/ ] ; then
			cp -rv /opt/scripts/desktop-defaults/jessie/lxqt/* /home/${rfs_username}/.config
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

#	#Disable LXDE's screensaver on autostart
#	if [ -f /etc/xdg/lxsession/LXDE/autostart ] ; then
#		sed -i '/xscreensaver/s/^/#/' /etc/xdg/lxsession/LXDE/autostart
#	fi

	#echo "CAPE=cape-bone-proto" >> /etc/default/capemgr

#	#root password is blank, so remove useless application as it requires a password.
#	if [ -f /usr/share/applications/gksu.desktop ] ; then
#		rm -f /usr/share/applications/gksu.desktop || true
#	fi

#	#lxterminal doesnt reference .profile by default, so call via loginshell and start bash
#	if [ -f /usr/bin/lxterminal ] ; then
#		if [ -f /usr/share/applications/lxterminal.desktop ] ; then
#			sed -i -e 's:Exec=lxterminal:Exec=lxterminal -l -e bash:g' /usr/share/applications/lxterminal.desktop
#			sed -i -e 's:TryExec=lxterminal -l -e bash:TryExec=lxterminal:g' /usr/share/applications/lxterminal.desktop
#		fi
#	fi

}
setup_A2DP () {
    wfile="/etc/dbus-1/system.d/pulseaudio-system.conf"
    line=$(grep -nr org.pulseaudio.Server ${wfile} | awk  -F ':'  '{print $1}')
    #add <allow send_destination="org.bluez"/>
    sed -i ''${line}'a <allow send_destination="org.bluez"/>' ${wfile}
    
    wfile="/etc/pulse/system.pa"
    line=$(grep -nr  module-suspend-on-idle ${wfile} | awk  -F ':'  '{print $1}')
    #remove load-module module-suspend-on-idle
    sed -i ''${line}'d' ${wfile}
    sed -i '$a ###Baozhu added'  ${wfile} 
    sed -i '$a ### Automatically load driver modules for Bluetooth hardware' ${wfile}
    sed -i '$a .ifexists module-bluetooth-policy.so'  ${wfile} 
    sed -i '$a load-module module-bluetooth-policy'  ${wfile} 
    sed -i '$a .endif'  ${wfile}
    sed -i '$a .ifexists module-bluetooth-discover.so'  ${wfile}
    sed -i '$a load-module module-bluetooth-discover'  ${wfile}
    sed -i '$a .endif'  ${wfile}
    
    #allow users of pulseaudio to communicate with bluetoothd
    wfile="/etc/dbus-1/system.d/bluetooth.conf"
    sed -i '$c <!-- allow users of pulseaudio to'  ${wfile}
    sed -i '$a communicate with bluetoothd -->'  ${wfile}
    sed -i '$a <policy group="pulse">'  ${wfile}
    sed -i '$a <allow send_destination="org.bluez"/>'  ${wfile}
    sed -i '$a </policy>'  ${wfile}
    sed -i '$a </busconfig>'  ${wfile}
    
    #add pulseaudio service
    wfile="/lib/systemd/system/pulseaudio.service"
    echo "[Unit]" > ${wfile}
    echo "Description=Pulse Audio" >> ${wfile}
    echo "After=bb-wl18xx-bluetooth.service" >> ${wfile}
    echo "[Service]" >> ${wfile}
    echo "Type=simple" >> ${wfile}
    echo "ExecStart=/usr/bin/pulseaudio --system --disallow-exit --disable-shm" >> ${wfile}
    echo "[Install]" >> ${wfile}
    echo "WantedBy=multi-user.target" >> ${wfile}
    systemctl enable pulseaudio.service || true
    
    #add a2dp users to root group
    usermod -a -G bluetooth root
    usermod -a -G pulse root
    usermod -a -G pulse-access root
    
    #add hci0 to udev rules
    wfile="/etc/udev/rules.d/10-local.rules"
    echo "# Power up bluetooth when hci0 is discovered" > ${wfile}
    echo "ACTION==\"add\", KERNEL==\"hci0\", RUN+=\"/bin/hciconfig hci0 up\"" >> ${wfile}
    
    #config alsa
    # wfile="/etc/asound.conf"
    # echo "pcm.!default {" > ${wfile}
    # echo "  type pulse" >> ${wfile}
    # echo "  fallback "sysdefault"" >> ${wfile}
    # echo "  hint {" >> ${wfile}
    # echo "    show on" >> ${wfile}
    # echo "    description "ALSA Output to pulseaudio"" >> ${wfile}
    # echo "  }" >> ${wfile}
    # echo "}" >> ${wfile}
    # echo "ctl.!default {" >> ${wfile}
    # echo "  type pulse" >> ${wfile}
    # echo "  fallback "sysdefault"" >> ${wfile}
    # echo "}" >> ${wfile}
}
install_pip_pkgs () {
	if [ -f /usr/bin/python ] ; then
		wget https://bootstrap.pypa.io/get-pip.py || true
		if [ -f get-pip.py ] ; then
			python get-pip.py
			rm -f get-pip.py || true

			if [ -f /usr/local/bin/pip ] ; then
				echo "Installing pip packages"
				git_repo="https://github.com/adafruit/adafruit-beaglebone-io-python.git"
				git_target_dir="/opt/source/adafruit-beaglebone-io-python"
				git_clone
				if [ -f ${git_target_dir}/.git/config ] ; then
					cd ${git_target_dir}/
					sed -i -e 's:4.1.0:3.4.0:g' setup.py
					python setup.py install
				fi
				pip install --upgrade PyBBIO
				pip install iw_parse
			fi
		fi
	fi
}

cleanup_npm_cache () {
	if [ -d /root/tmp/ ] ; then
		rm -rf /root/tmp/ || true
	fi

	if [ -d /root/.npm ] ; then
		rm -rf /root/.npm || true
	fi

	if [ -f /home/${rfs_username}/.npmrc ] ; then
		rm -f /home/${rfs_username}/.npmrc || true
	fi
}

install_git_repos () {
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

	git_repo="https://github.com/prpplague/Userspace-Arduino"
	git_target_dir="/opt/source/Userspace-Arduino"
	git_clone

	git_repo="https://github.com/cdsteinkuehler/beaglebone-universal-io.git"
	git_target_dir="/opt/source/beaglebone-universal-io"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		if [ -f ${git_target_dir}/config-pin ] ; then
			ln -s ${git_target_dir}/config-pin /usr/local/bin/
		fi
	fi

	git_repo="https://github.com/strahlex/BBIOConfig.git"
	git_target_dir="/opt/source/BBIOConfig"
	git_clone

	git_repo="https://github.com/prpplague/fb-test-app.git"
	git_target_dir="/opt/source/fb-test-app"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			make
		fi
		cd /
	fi

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

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_target_dir="/opt/source/dtb-4.4-ti"
	git_branch="4.4-ti"
	git_clone_branch

	if [ "x${image_type_mod}" = "x-bbb" ]; then
		git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
		git_target_dir="/opt/source/dtb-4.9-ti"
		git_branch="4.9-ti"
		git_clone_branch
	fi

	git_repo="https://github.com/beagleboard/bb.org-overlays"
	git_target_dir="/opt/source/bb.org-overlays"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
			is_kernel=$(echo ${repo_rcnee_pkg_version} | grep 3.8.13 || true)
			if [ "x${is_kernel}" = "x" ] ; then
				if [ -f /usr/bin/make ] ; then
					if [ ! -f /lib/firmware/BB-ADC-00A0.dtbo ] ; then
						make
						make install
						make clean
					fi
					update-initramfs -u -k ${repo_rcnee_pkg_version}
				fi
			fi
		fi
	fi

	git_repo="https://github.com/ungureanuvladvictor/BBBlfs"
	git_target_dir="/opt/source/BBBlfs"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			./autogen.sh
			./configure
			make
		fi
	fi

	git_repo="https://github.com/StrawsonDesign/Robotics_Cape_Installer"
	git_target_dir="/opt/source/Robotics_Cape_Installer"
	git_clone

	#beagle-tester
	git_repo="https://github.com/jadonk/beagle-tester"
	git_target_dir="/opt/source/beagle-tester"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		if [ -f /usr/lib/libroboticscape.so ] ; then
			cd ${git_target_dir}/
			if [ -f /usr/bin/make ] ; then
				make
				make install || true
				if [ "x${image_type_mod}" = "x-bbgw" ]; then
					if [ ! "x${image_type}" = "xtester-2gb" ] ; then
						systemctl disable beagle-tester.service || true
					fi
				fi
			fi
		fi
	fi
}

install_build_pkgs () {
	cd /opt/
	cd /
}

other_source_links () {
	rcn_https="https://rcn-ee.com/repos/git/u-boot-patches"

	mkdir -p /opt/source/u-boot_${u_boot_release}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-omap3_beagle-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0002-U-Boot-BeagleBone-Cape-Manager.patch
	mkdir -p /opt/source/u-boot_${u_boot_release_x15}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release_x15}/" ${rcn_https}/${u_boot_release_x15}/0001-beagle_x15-uEnv.txt-bootz-n-fixes.patch

	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt
	echo "u-boot_${u_boot_release_x15} : /opt/source/u-boot_${u_boot_release_x15}" >> /opt/source/list.txt

	chown -R ${rfs_username}:${rfs_username} /opt/source/
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
		#Starting with Jessie:
		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}

is_this_qemu

setup_system
setup_desktop
if [ "x${image_type_mod}" = "x-bbgw" ]; then
	setup_A2DP
fi

install_pip_pkgs
if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi
#install_build_pkgs
other_source_links
#unsecure_root
#
# install it here when almost whole system is set up (debian user exists)
npm config set unsafe-perm true
npm install bower -g

# add own repo
cat > /etc/apt/sources.list.d/iotcrafter.list <<EOF
deb [arch=all,armhf] http://iotcrafter.com:8888/iotc/bbb jessie main
EOF
# add repo key
wget -qO - http://iotcrafter.com:8888/iotc/iotcrafter.gpg.key | apt-key add -

apt-get -y update

echo iotc iotc/cpuid string BBB | debconf-set-selections
echo iotc iotc/kernvers string ${repo_rcnee_pkg_version} | debconf-set-selections
echo iotc iotc/load-overlays boolean false | debconf-set-selections

apt-get -y install iotc-core iotc-ide
dpkg-reconfigure -fnoninteractive -plow unattended-upgrades

# remove all iotc's settings
echo PURGE | debconf-communicate iotc

IOTC_INIT_REV=805c08877d5fadd25e34741210b553a963598a1c
wget -P /opt/iotc/bin/ https://raw.githubusercontent.com/softerra/iotc_scripts/${IOTC_INIT_REV}/board/iotc_init.sh
sed -i 's/^\(iotc_init_version=\).*$/\1"'${IOTC_INIT_REV}'"/' /opt/iotc/bin/iotc_init.sh
chmod 755 /opt/iotc/bin/iotc_init.sh
# force for now to use ifup for wifi (nevermind what is specified by the scirpt)
sed -i 's/^\(IOTC_WLAN_FORCE_IFUP=\).*$/\11/' /opt/iotc/bin/iotc_init.sh
