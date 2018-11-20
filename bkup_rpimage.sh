#!/bin/bash
# bkup_rpimage.sh by jinx
#
# Utility script to backup Raspberry Pi's SD Card to a sparse image file
# mounted as a filesystem in a file, allowing for efficient incremental
# backups using rsync

VERSION=v1.0
SDCARD=/dev/mmcblk0

# Echos traces with yellow text to distinguish from other output
trace () {
    echo -e "$(tput setaf 3)${1}$(tput sgr 0)"
}

# Echos en error string in red text and exit
error () {
    echo -e "$(tput setaf 1)${1}$(tput sgr 0)" >&2
    exit 1
}

# Creates a sparse $IMAGE clone of $SDCARD and attaches to $LOOPBACK
do_create () {
    trace "Creating sparse $IMAGE, the apparent size of $SDCARD"
    dd if=/dev/zero of=$IMAGE bs=$(blockdev --getss $SDCARD) count=0 seek=$(blockdev --getsz $SDCARD)

    if [ -s $IMAGE ]; then
        trace "Attaching $IMAGE to $LOOPBACK"
        losetup $LOOPBACK $IMAGE
    else
        error "$IMAGE was not created or has zero size"
    fi

    trace "Copying partition table from $SDCARD to $LOOPBACK"
    parted -s $LOOPBACK mklabel msdos
    sfdisk --dump $SDCARD | sfdisk --force $LOOPBACK

    trace "Formatting partitions"
    partx --add $LOOPBACK
    mkfs.vfat -I $LOOPBACK1
    mkfs.ext4 $LOOPBACK2
}

# Mounts the $IMAGE to $LOOPBACK (if needed) and $MOUNTDIR
do_mount () {
    # Check if do_create already attached the SD Image
    if [ $(losetup -f) = $LOOPBACK ]; then
        trace "Attaching $IMAGE to $LOOPBACK"
        losetup $LOOPBACK $IMAGE
        partx --add $LOOPBACK
    fi

    trace "Mounting $LOOPBACK1 and $LOOPBACK2 to $MOUNTDIR"
    if [ ! -n "$opt_mountdir" ]; then
        mkdir $MOUNTDIR
    fi
    mount $LOOPBACK2 $MOUNTDIR
    mkdir -p $MOUNTDIR/boot
    mount $LOOPBACK1 $MOUNTDIR/boot
}

# Rsyncs content of $SDCARD to $IMAGE if properly mounted
do_backup () {
    if mountpoint -q $MOUNTDIR; then
        trace "Starting rsync backup of / and /boot/ to $MOUNTDIR"
        if [ -n "$opt_log" ]; then
            rsync -aEvx --del --stats --log-file $LOG /boot/ $MOUNTDIR/boot/
            rsync -aEvx --del --stats --log-file $LOG / $MOUNTDIR/
        else
            rsync -aEvx --del --stats /boot/ $MOUNTDIR/boot/
            rsync -aEvx --del --stats / $MOUNTDIR/
        fi
    else
        trace "Skipping rsync since $MOUNTDIR is not a mount point"
    fi
}

# Unmounts the $IMAGE from $MOUNTDIR and $LOOPBACK
do_umount () {
    trace "Flushing to disk"
    sync; sync

    trace "Unmounting $LOOPBACK1 and $LOOPBACK2 from $MOUNTDIR"
    umount $MOUNTDIR/boot
    umount $MOUNTDIR
    if [ ! -n "$opt_mountdir" ]; then
        rmdir $MOUNTDIR
    fi

    trace "Detaching $IMAGE from $LOOPBACK"
    partx --delete $LOOPBACK
    losetup -d $LOOPBACK
}

# Compresses $IMAGE to $IMAGE.gz using a temp file during compression
do_compress () {
    trace "Compressing $IMAGE to ${IMAGE}.gz"
    pv -tpreb $IMAGE | gzip > ${IMAGE}.gz.tmp
    if [ -s ${IMAGE}.gz.tmp ]; then
        mv -f ${IMAGE}.gz.tmp ${IMAGE}.gz
        if [ -n "$opt_delete" ]; then
            rm -f $IMAGE
        fi
    fi
}

# Tries to cleanup after Ctrl-C interrupt
ctrl_c () {
    trace "Ctrl-C detected."

    if [ -s ${IMAGE}.gz.tmp ]; then
        rm ${IMAGE}.gz.tmp
    else
        do_umount
    fi

    if [ -n "$opt_log" ]; then
        trace "See rsync log in $LOG"
    fi

    error "SD Image backup process interrupted"
}

# Prints usage information
usage () {
    echo -e ""
    echo -e "$(basename $0) $VERSION by jinx"
    echo -e ""
    echo -e "Usage:"
    echo -e ""
    echo -e "    $(basename $0) $(tput bold)start$(tput sgr 0) [-clzdf] [-L logfile] [-i sdcard] sdimage"
    echo -e "    $(basename $0) $(tput bold)mount$(tput sgr 0) [-c] sdimage [mountdir]"
    echo -e "    $(basename $0) $(tput bold)umount$(tput sgr 0) sdimage [mountdir]"
    echo -e "    $(basename $0) $(tput bold)gzip$(tput sgr 0) [-df] sdimage"
    echo -e ""
    echo -e "    Commands:"
    echo -e ""
    echo -e "        $(tput bold)start$(tput sgr 0)  starts complete backup of RPi's SD Card to 'sdimage'"
    echo -e "        $(tput bold)mount$(tput sgr 0)  mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)"
    echo -e "        $(tput bold)umount$(tput sgr 0) unmounts the 'sdimage' from 'mountdir'"
    echo -e "        $(tput bold)gzip$(tput sgr 0)   compresses the 'sdimage' to 'sdimage'.gz"
    echo -e ""
    echo -e "    Options:"
    echo -e ""
    echo -e "        $(tput bold)-c$(tput sgr 0)         creates the SD Image if it does not exist"
    echo -e "        $(tput bold)-l$(tput sgr 0)         writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log"
    echo -e "        $(tput bold)-z$(tput sgr 0)         compresses the SD Image (after backup) to 'sdimage'.gz"
    echo -e "        $(tput bold)-d$(tput sgr 0)         deletes the SD Image after successful compression"
    echo -e "        $(tput bold)-f$(tput sgr 0)         forces overwrite of 'sdimage'.gz if it exists"
    echo -e "        $(tput bold)-L logfile$(tput sgr 0) writes rsync log to 'logfile'"
    echo -e "        $(tput bold)-i sdcard$(tput sgr 0)  specifies the SD Card location (default: $SDCARD)"
    echo -e ""
    echo -e "Examples:"
    echo -e ""
    echo -e "    $(basename $0) start -c /path/to/rpi_backup.img"
    echo -e "        starts backup to 'rpi_backup.img', creating it if it does not exist"
    echo -e ""
    echo -e "    $(basename $0) start /path/to/\$(uname -n).img"
    echo -e "        uses the RPi's hostname as the SD Image filename"
    echo -e ""
    echo -e "    $(basename $0) start -cz /path/to/\$(uname -n)-\$(date +%Y-%m-%d).img"
    echo -e "        uses the RPi's hostname and today's date as the SD Image filename,"
    echo -e "        creating it if it does not exist, and compressing it after backup"
    echo -e ""
    echo -e "    $(basename $0) mount /path/to/\$(uname -n).img /mnt/rpi_image"
    echo -e "        mounts the RPi's SD Image in /mnt/rpi_image"
    echo -e ""
    echo -e "    $(basename $0) umount /path/to/raspi-$(date +%Y-%m-%d).img"
    echo -e "        unmounts the SD Image from default mountdir (/mnt/raspi-$(date +%Y-%m-%d).img/)"
    echo -e ""
}

# Read the command from command line
case $1 in
    start|mount|umount|gzip) 
        opt_command=$1
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    --version)
        trace "$(basename $0) $VERSION by jinx"
        exit 0
        ;;
    *)
        error "Invalid command or option: $1\nSee '$(basename $0) --help' for usage";;
esac
shift 1

# Make sure we have root rights
if [ $(id -u) -ne 0 ]; then
    error "Please run as root. Try sudo."
fi

# Read the options from command line
while getopts ":czdflL:i:" opt; do
    case $opt in
        c)  opt_create=1;;
        z)  opt_compress=1;;
        d)  opt_delete=1;;
        f)  opt_force=1;;
        l)  opt_log=1;;
        L)  opt_log=1
            LOG=$OPTARG
            ;;
        i)  SDCARD=$OPTARG;;
        \?) error "Invalid option: -$OPTARG\nSee '$(basename $0) --help' for usage";;
        :)  error "Option -$OPTARG requires an argument\nSee '$(basename $0) --help' for usage";;
    esac
done
shift $((OPTIND-1))

# Read the sdimage path from command line
IMAGE=$1
if [ -z $IMAGE ]; then
    error "No sdimage specified"
fi

# Check if sdimage exists
if [ $opt_command = umount ] || [ $opt_command = gzip ]; then
    if [ ! -f $IMAGE ]; then
        error "$IMAGE does not exist"
    fi
else
    if [ ! -f $IMAGE ] && [ ! -n "$opt_create" ]; then
        error "$IMAGE does not exist\nUse -c to allow creation"
    fi
fi

# Check if we should compress and sdimage.gz exists
if [ -n "$opt_compress" ] || [ $opt_command = gzip ]; then
    if [ -s ${IMAGE}.gz ] && [ ! -n "$opt_force" ]; then
        error "${IMAGE}.gz already exists\nUse -f to force overwriting"
    fi
fi

# Define default rsync logfile if not defined
if [ -z $LOG ]; then
    LOG=${IMAGE}-$(date +%Y%m%d%H%M%S).log
fi

# Identify which loopback device to use
LOOPBACK=$(losetup -j $IMAGE | grep -o ^[^:]*)
if [ $opt_command = umount ]; then
    if [ -z $LOOPBACK ]; then
        error "No /dev/loop<X> attached to $IMAGE"
    fi
elif [ ! -z $LOOPBACK ]; then
    error "$IMAGE already attached to $LOOPBACK mounted on $(grep ${LOOPBACK}p2 /etc/mtab | cut -d ' ' -f 2)/"
else
    LOOPBACK=$(losetup -f)
fi
LOOPBACK1=${LOOPBACK}p1
LOOPBACK2=${LOOPBACK}p2

# Read the optional mountdir from command line
MOUNTDIR=$2
if [ -z $MOUNTDIR ]; then
    MOUNTDIR=/mnt/$(basename $IMAGE)/
else
    opt_mountdir=1
    if [ ! -d $MOUNTDIR ]; then
        error "Mount point $MOUNTDIR does not exist"
    fi
fi

# Check if default mount point exists
if [ $opt_command = umount ]; then
    if [ ! -d $MOUNTDIR ]; then
        error "Default mount point $MOUNTDIR does not exist"
    fi
else
    if [ ! -n "$opt_mountdir" ] && [ -d $MOUNTDIR ]; then
        error "Default mount point $MOUNTDIR already exists"
    fi
fi

# Trap keyboard interrupt (ctrl-c)
trap ctrl_c SIGINT

# Check for dependencies
for c in dd losetup parted sfdisk partx mkfs.vfat mkfs.ext4 mountpoint rsync; do
    command -v $c >/dev/null 2>&1 || error "Required program $c is not installed"
done
if [ -n "$opt_compress" ] || [ $opt_command = gzip ]; then
    for c in pv gzip; do
        command -v $c >/dev/null 2>&1 || error "Required program $c is not installed"
    done
fi

# Do the requested functionality
case $opt_command in
    start)
            trace "Starting SD Image backup process"
            if [ ! -f $IMAGE ] && [ -n "$opt_create" ]; then
                do_create
            fi
            do_mount
            do_backup
            do_umount
            if [ -n "$opt_compress" ]; then
                do_compress
            fi
            trace "SD Image backup process completed."
            if [ -n "$opt_log" ]; then
                trace "See rsync log in $LOG"
            fi
            ;;
    mount)
            if [ ! -f $IMAGE ] && [ -n "$opt_create" ]; then
                do_create
            fi
            do_mount
            trace "SD Image has been mounted and can be accessed at:\n    $MOUNTDIR"
            ;;
    umount)
            do_umount
            ;;
    gzip)
            do_compress
            ;;
    *)
            error "Unknown command: $opt_command"
            ;;
esac

exit 0
