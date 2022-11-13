#!/bin/bash

OUT="$1"
DIR="$2"

if [ "$DIR" == "" ]
then
	DIR="fmk/rootfs"
fi

if [ "$OUT" == "" ]
then
	OUT="www"
fi

if [ $UID -ne 0 ]
then
	SUDO="sudo"
fi

eval $(cat shared-ng.inc)
HTTPD="$DIR/usr/sbin/httpd"
WWW="$DIR/etc/www"
KEYFILE="$DIR/webcomp.key"

echo -e "Firmware Mod Kit (ddwrt-gui-extract) $VERSION, (c)2013 Craig Heffner, Jeremy Collake\nhttp://www.bitsum.com\n"

if [ ! -d "$DIR" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
	echo -e "Usage: $0 [output directory] [rootfs directory]\n"
	exit 1
fi

if [ ! -e "$HTTPD" ] || [ ! -e "$WWW" ]
then
	echo "Unable to locate httpd / www files in directory $DIR. Quitting..."
	exit 1
fi

# Extract!
# key file is written to rootfs, and since may have root ownership, sudo
TMPFILE=`mktemp /tmp/$0.XXXXXX`
./src/webcomp-tools/webdecomp --httpd="$HTTPD" --www="$WWW" --dir="$OUT" --key="$TMPFILE" --extract
$SUDO cp "$TMPFILE" "$KEYFILE"

