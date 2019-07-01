#!/bin/bash -e

cd $(cd $(dirname $0); pwd)/..

BUILD_SYS="image-builder"
DOCKER_IMG="${BUILD_SYS}-iotcrafter"
DOCKER_IMG_TAG="stretch"
DOCKER="docker"
DOCKER_CONTAINER_SUFFIX=${1:-iotc}
set +e
$DOCKER ps >/dev/null 2>&1
if [ $? != 0 ]; then
	DOCKER="sudo docker"
fi
if ! $DOCKER ps >/dev/null; then
	echo "error connecting to docker:"
	$DOCKER ps
	exit 1
fi

DOCKER_OPTS=""
if [ "$1" = "docker" ]; then
	echo "(Re-)building docker image only.."
	DOCKER_OPTS=$2 #e.g.--no-cache
	docker image rm "$DOCKER_IMG:$DOCKER_IMG_TAG"
else
	echo "Building docker image as need.."
fi

$DOCKER build \
	$DOCKER_OPTS \
	--build-arg DEB_DISTRO=$DOCKER_IMG_TAG \
	-t "$DOCKER_IMG:$DOCKER_IMG_TAG" \
	-f iotcrafter/Dockerfile.iotcrafter iotcrafter/
RC=$?
$DOCKER rmi $(docker images -f "dangling=true" -q)

if [ "$1" = "docker" -o $RC -ne 0 ]; then
	exit $RC
fi

set -e
echo "Building Debian image for BeagleBone.."

if [ -f config ]; then
	source config
fi

if [ -z "${IMG_NAME}" ]; then
	echo "IMG_NAME not set in 'config'" 1>&2
	echo 1>&2
fi

if [ -z "${IMG_CONF}" ]; then
	echo "IMG_CONF not set in 'config', build default" 1>&2
	IMG_CONF=iotcrafter-debian-stretch-v4.9
fi

CONTAINER_NAME="${BUILD_SYS}_${DOCKER_CONTAINER_SUFFIX}_work"
CONTINUE=${CONTINUE:-0}
CONTAINER_EXISTS=$($DOCKER ps -a --filter name="$CONTAINER_NAME" -q)
CONTAINER_RUNNING=$($DOCKER ps --filter name="$CONTAINER_NAME" -q)

if [ "$CONTAINER_RUNNING" != "" ]; then
	echo "The build is already running in container $CONTAINER_NAME. Aborting."
	exit 1
fi

# create dirs having respective docker volumes managed by original build scripts
mkdir -p ignore
mkdir -p git
buildCommand="dpkg-reconfigure qemu-user-static && ./iotcrafter/build.sh; \
				BUILD_RC=\$?; \
				iotcrafter/postbuild.sh \$BUILD_RC"

# TODO: consider supporting 'continue'
if [ "$CONTAINER_EXISTS" != "" ] && [ "$CONTINUE" = "1" ]; then
	echo "Continue $CONTAINER_NAME => ${CONTAINER_NAME}_cont"

	trap "echo 'got CTRL+C... please wait 5s';docker stop -t 5 ${CONTAINER_NAME}_cont" SIGINT SIGTERM
	time $DOCKER run --privileged \
		--volumes-from="${CONTAINER_NAME}" \
		--name "${CONTAINER_NAME}_cont" \
		-e IMG_NAME=${IMG_NAME} \
		-e IMG_CONF=${IMG_CONF} \
		-v "$(pwd):/${BUILD_SYS}" -w "/${BUILD_SYS}" \
		$DOCKER_IMG:$DOCKER_IMG_TAG \
		bash -o pipefail -c "${buildCommand}" &
	wait "$!"

	# remove old container and rename this to usual name
	echo "Removing old container"
	$DOCKER container rm -v $CONTAINER_NAME
	echo "Renaming ${CONTAINER_NAME}_cont => ${CONTAINER_NAME}"
	$DOCKER container rename ${CONTAINER_NAME}_cont ${CONTAINER_NAME}

else
	if [ "$CONTAINER_EXISTS" != "" ]; then
		echo "Removing old container and start anew"
		$DOCKER container rm -v $CONTAINER_NAME
	else
		echo "Start a new container $CONTAINER_NAME"
	fi

	trap "echo 'got CTRL+C... please wait 5s';docker stop -t 5 ${CONTAINER_NAME}" SIGINT SIGTERM
	time $DOCKER run --privileged \
		--name "${CONTAINER_NAME}" \
		-e IMG_NAME=${IMG_NAME} \
		-e IMG_CONF=${IMG_CONF} \
		-v "$(pwd):/${BUILD_SYS}" -w "/${BUILD_SYS}" \
		$DOCKER_IMG:$DOCKER_IMG_TAG \
		bash -o pipefail -c "${buildCommand}" &
	wait "$!"
fi

rmdir git
rmdir ignore

build_rc=$(cat iotcrafter/build_rc)
rm -f iotcrafter/build_rc

echo "Done. RC=${build_rc}. Your image(s) should be in deploy/ on success"

exit ${build_rc:-1}
