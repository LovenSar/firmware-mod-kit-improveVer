#!/bin/bash

IMG="${1}"
DIR="${2}"

if [ "${DIR}" = "" ]
 then
	DIR="fmk"
fi

# Need to extract file systems as ROOT
if [ "$(id -ru)" != "0" ]
 then
	SUDO="sudo"
else
	SUDO=""
fi

IMG=$(readlink -f $IMG)
DIR=$(readlink -f $DIR)

# Make sure we're operating out of the FMK directory
cd $(dirname $(readlink -f $0))

# Source in/Import shared settings. ${DIR} MUST be defined prior to this!
. ./shared-ng.inc

printf "Firmware Mod Kit (build-ng) ${VERSION}, (c)2011-2013 Craig Heffner, Jeremy Collake\n\n"

# Check usage
if [ "${IMG}" = "" ] || [ "${IMG}" = "-h" ]
 then
	printf "Usage: ${0} <firmware image>\n\n"
	exit 1
fi

if [ ! -f "${IMG}" ];
then
	echo "File does not exist!"
	exit 1
fi

if [ -e "${DIR}" ]
 then
	echo "Directory ${DIR} already exists! Quitting..."
	exit 1
fi

# Check if FMK has been built, and if not, build it
if [ ! -e "./src/crcalc/crcalc" ]
 then
	echo "Firmware-Mod-Kit has not been built yet. Building..."
	cd src && ./configure && make

	if [ ${?} -eq 0 ]
	 then
		cd -
	else
		echo "Build failed! Quitting..."
		exit 1
	fi
fi

# Get the size, in bytes, of the target firmware image
FW_SIZE=$(ls -l "${IMG}" | cut -d' ' -f5)

# Create output directories
mkdir -p "${DIR}/logs"
mkdir -p "${DIR}/image_parts"

echo "Scanning firmware..."

# Log binwalk results to the ${BINLOG} file, disable default filters, exclude invalid results,
# and search only for trx, uimage, dlob, squashfs, and cramfs results.
#${BINWALK} -f "${BINLOG}" -d -x invalid -y trx -y uimage -y dlob -y squashfs -y cramfs "${IMG}"
${BINWALK} -f "${BINLOG}" "${IMG}"

# Set Internal Field Separator (IFS) via two lines to newline only (bashism would be $'\n')
IFS='
'

# Header image offset is ALWAYS 0. Header checksums are simply updated by build-ng.sh.
HEADER_IMAGE_OFFSET=0

# Loop through binwalk log file
for LINE in IFS='
'$(sort -n ${BINLOG} | grep -v -e '^DECIMAL' -e '^---')
 do
	# Get decimal file offset and the first word of the description
	OFFSET=$(echo ${LINE} | awk '{print $1}')
	DESCRIPTION=$(echo ${LINE} | awk '{print tolower($3)}')

	# Offset 0 is firmware header
	if [ "${OFFSET}" = "0" ]
	 then
		HEADER_OFFSET=${OFFSET}
		HEADER_TYPE=${DESCRIPTION}
		HEADER_SIZE=$(echo ${LINE} | sed -e 's/.*header size: //' | cut -d' ' -f1)
		HEADER_IMAGE_SIZE=$(echo ${LINE} | sed -e 's/.*image size: //' | cut -d' ' -f1)

	# Check to see if this line is a file system entry
	elif [ "$(echo ${LINE} | grep -i filesystem)" != "" ]
	 then
		FS_OFFSET=${OFFSET}
		FS_TYPE=${DESCRIPTION}

		# Need to know endianess for re-assembly
		if [ "$(echo ${LINE} | grep -i 'big endian')" != "" ]
		 then
			ENDIANESS="-be"
		else
			ENDIANESS="-le"
		fi

		# Check for LZMA compression in the file system. If not present, assume gzip.
		# This is only used for squashfs 4.0 images.
		if [ "$(echo ${LINE} | grep -i 'lzma')" != "" ]
		 then
			FS_COMPRESSION="lzma"
		else
			FS_COMPRESSION="gzip"
		fi

		# Check for a block size (used only by mksquashfs)
		if [ "$(echo ${LINE} | grep -i 'blocksize')" != "" ]
		then
			set -f
			IFS=,
			for fsparam in ${LINE}
			do
				if [[ $fsparam = *blocksize* ]]; then
				  fsparam="${fsparam##*blocksize: }"
				  FS_BLOCKSIZE="${fsparam%* bytes}"
				  break
				fi
			done
		fi
		set +f; unset IFS
	fi
done

# Header image size is everything from the header image offset (0) up to the file system
HEADER_IMAGE_SIZE=$((${FS_OFFSET}-${HEADER_IMAGE_OFFSET}))

# Extract the header + image up to the file system
echo "Extracting ${HEADER_IMAGE_SIZE} bytes of ${HEADER_TYPE} header image at offset ${HEADER_IMAGE_OFFSET}"
dd if="${IMG}" bs=${HEADER_IMAGE_SIZE} skip=${HEADER_IMAGE_OFFSET} count=1 of="${HEADER_IMAGE}" 2>/dev/null

if [ "${FS_OFFSET}" != "" ]
 then
	echo "Extracting ${FS_TYPE} file system at offset ${FS_OFFSET}"
	dd if="${IMG}" bs=${FS_OFFSET} skip=1 of="${FSIMG}" 2>/dev/null
else
	echo "ERROR: No supported file system found! Aborting..."
	rm -rf "${DIR}"
	exit 1
fi

FOOTER_SIZE=0
FOOTER_OFFSET=0

# Try to determine if there is a footer at the end of the firmware image.
# Grab the last 10 lines of a hexdump of the firmware image, excluding the
# last line in the hexdump. Reverse the line order and replace any lines
# that start with '*' with the word 'FILLER'.
for LINE in $(hexdump -C ${IMG} | tail -11 | head -10 | sed -n '1!G;h;$p' | sed -e 's/^*/FILLER/')
 do
	if [ "${LINE}" = "FILLER" ]
	 then
		break
	else
		FOOTER_SIZE=$((${FOOTER_SIZE}+16))
	fi
done

# If a footer was found, dump it out
if [ "${FOOTER_SIZE}" != "0" ]
 then
	FOOTER_OFFSET=$((${FW_SIZE}-${FOOTER_SIZE}))
	echo "Extracting ${FOOTER_SIZE} byte footer from offset ${FOOTER_OFFSET}"
	dd if="${IMG}" bs=1 skip=${FOOTER_OFFSET} count=${FOOTER_SIZE} of="${FOOTER_IMAGE}" 2>/dev/null
else
	FOOTER_OFFSET=${FW_SIZE}
fi

# Log the parsed values to the CONFLOG for use when re-building the firmware
echo "FW_SIZE='${FW_SIZE}'" > ${CONFLOG}
echo "HEADER_TYPE='${HEADER_TYPE}'" >> ${CONFLOG}
echo "HEADER_SIZE='${HEADER_SIZE}'" >> ${CONFLOG}
echo "HEADER_IMAGE_SIZE='${HEADER_IMAGE_SIZE}'" >> ${CONFLOG}
echo "HEADER_IMAGE_OFFSET='${HEADER_IMAGE_OFFSET}'" >> ${CONFLOG}
echo "FOOTER_SIZE='${FOOTER_SIZE}'" >> ${CONFLOG}
echo "FOOTER_OFFSET='${FOOTER_OFFSET}'" >> ${CONFLOG}
echo "FS_TYPE='${FS_TYPE}'" >> ${CONFLOG}
echo "FS_OFFSET='${FS_OFFSET}'" >> ${CONFLOG}
echo "FS_COMPRESSION='${FS_COMPRESSION}'" >> ${CONFLOG}
echo "FS_BLOCKSIZE='${FS_BLOCKSIZE}'" >> ${CONFLOG}
echo "ENDIANESS='${ENDIANESS}'" >> ${CONFLOG}

# Extract the file system and save the MKFS variable to the CONFLOG
case ${FS_TYPE} in
	"squashfs")
		echo "Extracting squashfs files..."
		${SUDO} ./unsquashfs_all.sh "${FSIMG}" "${ROOTFS}" 2>/dev/null | grep MKFS >> "${CONFLOG}"
		;;
	"cramfs")
		echo "Extracting CramFS file system..."
		${SUDO} ./uncramfs_all.sh "${FSIMG}" "${ROOTFS}" ${ENDIANESS} 2>/dev/null | grep MKFS >> "${CONFLOG}"
		;;
	*)
		echo "Unsupported file system '${FS_TYPE}'! Quitting..."
		rm -rf "${DIR}"
		exit 1
		;;
esac

# Check if file system extraction was successful
if [ ${?} -eq 0 ]
 then
	echo "Firmware extraction successful!"
	echo "Firmware parts can be found in '${DIR}/*'"
else
	echo "Firmware extraction failed!"
	rm -rf "${DIR}"
	exit 1
fi

exit 0
