#!/bin/bash

FSIMG="$1"
ROOTFS="$2"
ENDIANESS="$3"
MKFS=""

function finish
{
	rm -f "$FSIMG.le"
	echo "MKFS=\"$MKFS\""
}

if [ "$FSIMG" == "" ] || [ "$FSIMG" == "-h" ]
then
	echo "Usage: $(basename $0) <cramfs image> [output directory] [-be | -le]\n"
	exit 1
fi

if [ $UID -ne 0 ]
then
	SUDO="sudo"
fi

if [ "$ENDIANESS" == "" ]
then
	if [ "$(file $FSIMG | grep 'big endian')" != "" ]
	then
		ENDIANESS="-be"
	fi
fi

if [ "$ROOTFS" == "" ]
then
	ROOTFS="./cramfs-root"
	BDIR=$ROOTFS
	I=1

	while [ -e $ROOTFS ]
	do
		ROOTFS=$BDIR-$I
		((I=$I+1))
	done
fi

FSIMG=$(readlink -f $FSIMG)
ROOTFS=$(readlink -f $ROOTFS)

# Make sure we're operating out of the FMK directory
cd $(dirname $(readlink -f $0))

if [ "$ENDIANESS" == "-be" ]
then
	./src/cramfsswap/cramfsswap "$FSIMG" "$FSIMG.le"
else
	cp "$FSIMG" "$FSIMG.le"
fi

if [ -e "$FSIMG.le" ]
then
	# If this is an OpenRG firmware, try uncramfs-lzma first.
	if [ "$(strings "$FSIMG.le" | grep openrg)" != "" ]
	then
		./src/uncramfs-lzma/uncramfs-lzma "$ROOTFS" "$FSIMG.le" 2>/dev/null
		if [ $? -eq 0 ]
		then
			# Does not exist, will not be able to re-build the file system!
			MKFS="./src/uncramfs-lzma/mkcramfs-lzma"
			finish
			exit 0
		fi
	fi

	./src/cramfs-2.x/cramfsck -x "$ROOTFS" "$FSIMG.le" 2>/dev/null
	if [ $? -eq 0 ]
	then
		MKFS="./src/cramfs-2.x/mkcramfs"
		finish
		exit 0
	fi

	./src/uncramfs/uncramfs "$ROOTFS" "$FSIMG.le" 2>/dev/null
	if [ $? -eq 0 ]
	then
		MKFS="./src/cramfs-2.x/mkcramfs"
		finish
		exit 0
	fi

	./src/uncramfs-lzma/uncramfs-lzma "$ROOTFS" "$FSIMG.le" 2>/dev/null
	if [ $? -eq 0 ]
	then
		# Does not exist, will not be able to re-build the file system!
		MKFS="./src/uncramfs-lzma/mkcramfs-lzma"
		finish
		exit 0
	fi
fi

echo "File extraction failed!"
finish
exit 1
