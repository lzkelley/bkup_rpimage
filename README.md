# bkup_rpimage
Script to backup a Raspberry Pi disk image

## Author / Origin:
Script developed on the RaspberryPi.org forums: [The Raspberry Pi Backup Thread](https://www.raspberrypi.org/forums/viewtopic.php?f=63&t=12079).
The script, as copied over to github.com, was primarily written by user: `jinx`.
I found this via [a raspberrypi.stackexchange.com answer](http://raspberrypi.stackexchange.com/a/5431/61087) by user: `ppumpkin`.

[The script was taken from here](https://www.raspberrypi.org/forums/viewtopic.php?p=638345#p638345), a post from `Mon Nov 10, 2014 7:05 am`.
I copied the attached file on `Wed Feb 01, 2017` to this git repository.


## Usage from Jinx and corrected the mistake of using rsync instead of start in the examples

bkup_rpimage.sh v1.0 by jinx

### Usage:

* bkup_rpimage.sh start [-cslzdf] [-L logfile] sdimage
* bkup_rpimage.sh mount [-c] sdimage [mountdir]
* bkup_rpimage.sh umount sdimage [mountdir]
* bkup_rpimage.sh gzip [-df] sdimage

### Commands:

* *start* - starts complete backup of RPi's SD Card to 'sdimage'
* *mount* - mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
* *umount* - unmounts the 'sdimage' from 'mountdir'
* *gzip* - compresses the 'sdimage' to 'sdimage'.gz

### Options:

* -c creates the SD Image if it does not exist
* -l writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
* -z compresses the SD Image (after backup) to 'sdimage'.gz
* -d deletes the SD Image after successful compression
* -f forces overwrite of 'sdimage'.gz if it exists
* -L logfile writes rsync log to 'logfile'
* -s define the size of the image file

### Examples:

Start backup to `rpi_backup.img`, creating it if it does not exist:
```
bkup_rpimage.sh start -c /path/to/rpi_backup.img
```

Start backup to `rpi_backup.img`, creating it if it does not exist limiting 
 the size to 8000Mb
```
bkup_rpimage.sh start -s 8000 -c /path/to/rpi_backup.img
```


Use the RPi's hostname as the SD Image filename:
```
bkup_rpimage.sh start /path/to/$(uname -n).img
```

Use the RPi's hostname and today's date as the SD Image filename,
creating it if it does not exist, and compressing it after backup:
```
bkup_rpimage.sh start -cz /path/to/$(uname -n)-$(date +%Y-%m-%d).img
```

Mount the RPi's SD Image in `/mnt/rpi_image`:
```
bkup_rpimage.sh mount /path/to/$(uname -n).img /mnt/rpi_image
```

Unmount the SD Image from default mountdir (`/mnt/raspi-2014-11-10.img/`):
```
bkup_rpimage.sh umount /path/to/raspi-2014-11-10.img
```
