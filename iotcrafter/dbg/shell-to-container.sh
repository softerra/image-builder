#!/bin/bash -ex

cd $(cd $(dirname $0); pwd)/../..

BUILD_SYS="image-builder"
DOCKER_IMG="${BUILD_SYS}-iotcrafter"
DOCKER_IMG_TAG="stretch"
DOCKER="docker"
DOCKER_CONTAINER_SUFFIX=${1:-iotc}

if [ -f config ]; then
	source config
fi

CONTAINER_NAME="${BUILD_SYS}_${DOCKER_CONTAINER_SUFFIX}_work"
CONTAINER_EXISTS=$($DOCKER ps -a --filter name="$CONTAINER_NAME" -q)
CONTAINER_RUNNING=$($DOCKER ps --filter name="$CONTAINER_NAME" -q)

if [ "$CONTAINER_RUNNING" != "" ]; then
	echo "The build is already running, shell to running container ${CONTAINER_NAME}..."
	${DOCKER} exec -ti ${CONTAINER_NAME} /bin/bash
	exit 0
fi

mkdir -p ignore
mkdir -p git

if [ "$CONTAINER_EXISTS" != "" ]; then
	$DOCKER run -it --privileged \
		--volumes-from="${CONTAINER_NAME}" \
		--name "${CONTAINER_NAME}_debug" \
		-e IMG_NAME=${IMG_NAME} \
		-e IMG_CONF=${IMG_CONF} \
		${kernelMount} \
		-v "$(pwd):/${BUILD_SYS}" -w "/${BUILD_SYS}" \
		$DOCKER_IMG:$DOCKER_IMG_TAG \
		/bin/bash
fi

rmdir git
rmdir ignore

