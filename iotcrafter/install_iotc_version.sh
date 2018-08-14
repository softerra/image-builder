
VERFILE=${tempdir}/opt/iotc/etc/version.json
install -d -m 755 $(dirname $VERFILE)
install -m 644 ${OIB_DIR}/target/iotcrafter/version.json $(dirname $VERFILE)
. ${OIB_DIR}/iotcrafter/iotc-version
sed -i -e 's/"image"[^"]*"[^"]*\(".*\)$/"image": "'$IOTC_VERSION'\1/' $VERFILE
sed -i -e 's/"image-build"[^"]*"[^"]*\(".*\)$/"image-build": "'$IMG_NAME'\1/' $VERFILE
