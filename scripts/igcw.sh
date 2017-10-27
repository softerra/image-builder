#!/bin/sh

# The script is to be placed to scripts/ alone with chroot.sh
# See args below in 'MAIN' section

# Iotcrafter Git Clone Workaround (igcw_ prefix)

igcw_name='igcw.sh'		# $(basename $0) may not be the same! (when the script is included)
igcw_s_port=51810
igcw_c_port=50712
igcw_recv_line_text=''

#-----------------
# Common Functions
#-----------------

igcw_require_uid0()
{
	if [ "$(id -u)" != "0" ]; then
		echo "$igcw_name: should be called by root (with sudo)"
		exit 1
	fi
}

#$1 - port
igcw_exch_name()
{
	if [ "$1" = "$igcw_s_port" ]; then
		echo "server"
	elif [ "$1" = "$igcw_c_port" ]; then
		echo "client"
	else
		echo "common"
	fi
}

# $1 - port
# $2 - line to send
igcw_send_line()
{
	sleep 1
	echo "$2" | nc -q1 127.0.0.1 $1
}

# $1 - port
igcw_recv_line()
{
	local line="$(nc -q3 -l 127.0.0.1 -p $1)"
	echo "$igcw_name ($(igcw_exch_name $1)): igcw_recv_line_rc=$?"
	igcw_recv_line_text="$line"
}

#-------------------------------
# CHROOT-side Functions (client)
#-------------------------------

# substitute in chroot scripts 'git clone XXX..' for 'git_clone XXX..'
igcw_git_clone_chroot()
{
	echo "$igcw_name (chroot): need to clone: '$*'"
	igcw_send_line $igcw_s_port "git clone $*"
	echo -n "$igcw_name (chroot): request sent, waiting answer.."
	igcw_recv_line $igcw_c_port
	echo "$igcw_name (chroot): got answer: '$igcw_recv_line_text'"
}

#----------------------------------
# NO-CHROOT-side Functions (server)
#----------------------------------

# $1 - script's directory
igcw_main_chroot_patch()
{
	if [ -f $1/chroot.sh.bak ]; then
		echo "$igcw_name (main): chroot.sh.bak is found"
		if [ -f $1/chroot.sh ]; then
			echo "$igcw_name (main): assume chroot.sh is already patched"
			return 0
		fi
		mv -f $1/chroot.sh.bak $1/chroot.sh
		echo "$igcw_name (main): restored original chroot.sh"
	fi

	# save original chroot.sh
	cp -f $1/chroot.sh $1/chroot.sh.bak
	echo "$igcw_name (main): chroot.sh backed up"

	# embed slef-call into the main chroot.sh script
	sed -i -r '
s/^(\s*)sudo\s+chroot\s+(\S+)\s+.*bash\s+\S+\s+(\w+.sh)$/\
\1sudo \${OIB_DIR}\/scripts\/'${igcw_name}' start \2 \&\
\1sudo \${OIB_DIR}\/scripts\/'${igcw_name}' patch \2 \3\
&\
\1sudo \${OIB_DIR}\/scripts\/'${igcw_name}' clean \2/
' $1/chroot.sh

	echo "$igcw_name (main): chroot.sh patched"
	#cp $1/chroot.sh $1/chroot.sh.patched
	return 0
}

# $1 - script's directory
igcw_main_chroot_restore()
{
	if [ -f $1/chroot.sh.bak ]; then
		mv -f $1/chroot.sh.bak $1/chroot.sh
		echo "$igcw_name (main): chroot.sh restored"
	fi
	return 0
}

# executed by 'server' whose current dir is chroot's root dir
igcw_git_clone()
{
	# target dir starts with slash /<path>
	local args=''
	local param=''
	while [ $# -gt 0 ]; do
		param=$1
		shift
		# cut off leading slash
		echo "$param" | grep -q '^[/].*' && param=${param#/}
		args="$args $param"
	done

	git clone $args
	local rc=$?

	echo "$igcw_name (server): cloned: $rc"
	return $rc
}

igcw_clone_server_start()
{
	echo "$igcw_name: start clone server -> $(pwd)"

	local args=''
	local rc=0
	while [ 1 ]; do
		echo "$igcw_name (server): wating next line.."
		igcw_recv_line $igcw_s_port
		echo "$igcw_name (server): line got: '$igcw_recv_line_text'"

		[ "$igcw_recv_line_text" = "exit" ] && break

		echo "$igcw_recv_line_text" | grep -qE '^git clone\s+.*$'
		if [ $? -eq 0 ]; then
			args=${igcw_recv_line_text#git clone}
			echo "$igcw_name (server): args to clone: '$args'"
			igcw_git_clone $args
		else
			echo "$igcw_name (server): line ignored: '$igcw_recv_line_text'"
		fi

		rc=$?
		igcw_send_line $igcw_c_port "$rc"
		echo "$igcw_name (server): answer sent: $rc"
	done

	echo "$igcw_name (server): stopped"
	return 0
}

igcw_clone_server_stop()
{
	echo "$igcw_name: stop clone server"
	igcw_send_line $igcw_s_port 'exit'
	return 0
}

# $1 script to patch
igcw_patch_script()
{
	sed -i '2 i\
\n. $(dirname $0)/'$igcw_name'' $1

	sed -i -r 's/^(\s*)git\s+clone\s+(.*)$/\1igcw_git_clone_chroot \2/' $1

	#cp -f $1 $1.patched
	return 0
}

# MAIN (server/client depending where it called/included from)
# $1:
#	- main-patch:	back up scripts/chroot.sh, patch it for git clone workaround
#	- main-restore:	restore scripts/chroot.sh
#	- start: 		start git clone server
#	- patch:		copy self to the same dir with chroot script, 
#					patch a 'chroot' script to use 'igcw_git_clone_chroot' instead of 'git clone'
#	- clean:		remove self from rootfs, stop git clone server
igcw_main()
{
	local my_dir="$(realpath $(dirname $0))"

	case "$1" in
		main-patch)
			igcw_main_chroot_patch $my_dir
			;;
		main-restore)
			igcw_main_chroot_restore $my_dir
			;;

		start)	#SHOULD be run in background before chroot script started
			igcw_require_uid0
			[ -z "$2" -o ! -d "$2" ] && echo "$igcw_name: rootfs directory '$2' is wrong" && exit 1
			cd $2
			igcw_clone_server_start
			;;

		patch)
			igcw_require_uid0
			[ -z "$2" -o ! -d "$2" ] && echo "$igcw_name: rootfs directory '$2' is wrong" && exit 1
			cd $2
			[ ! -f "$3" ] && echo "$igcw_name: script to be patched '$3' is wrong" && exit 1
			cp -f ${my_dir}/${igcw_name} ./
			igcw_patch_script $3
			;;
		clean)
			igcw_require_uid0
			[ -z "$2" -o ! -d "$2" ] && echo "$igcw_name: rootfs directory '$2' is wrong" && exit 1
			cd $2
			rm -f ${igcw_name}
			igcw_clone_server_stop
			;;

		*)
			echo "$igcw_name: incorrectly called"
			exit 1
			;;
	esac
}

if [ "$(basename $0)" = "$igcw_name" ]; then
	echo "$igcw_name: called"
	# don't use it on armv7l
	host_arch=$(uname -m)
	echo "running on '${host_arch}'"
	if [ "${host_arch}" = "armv7l" ]; then
		echo "igcw is not needed"
	else
		igcw_main $*
	fi
else
	echo "$igcw_name: included"
	# nothing to do, just expose functions
fi
