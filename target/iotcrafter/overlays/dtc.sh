#!/bin/sh -e

# $1 - kernel tree root
# $2 - destination dir

build_dir=$(cd $(dirname $0); pwd)

kern_src=$1
#kern_src=/home/alex/tests/kernel/bb-kernel-4.9.83-ti-r103/usr/src/linux-headers-4.9.83-ti-r103
dest_dir=$2

kern_inc=${kern_src}/include
kern_dtc=${kern_src}/scripts/dtc/dtc

# Check dtc
${kern_dtc} -v
overlays=$(cd $build_dir; ls *.dts)
echo "Found overlays: $overlays"
echo "Create dest dir as need: ${dest_dir}"
mkdir -p ${dest_dir}

for ov in $overlays; do
	# preprocess
	cpp -nostdinc -I${kern_inc} -undef -D__DTS__ -x assembler-with-cpp \
		-o ${build_dir}/${ov}.pp ${build_dir}/${ov}
	$kern_dtc -O dtb -o ${build_dir}/${ov%.dts}.dtbo -b 0 -@ ${build_dir}/${ov}.pp

	cp ${build_dir}/${ov%.dts}.dtbo ${dest_dir}/
done

echo "Overlays built and installed"
