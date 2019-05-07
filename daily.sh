#!/bin/bash
#
#	*EXAMPLE* Script for daily backup
#	
#	Before the backup takes place a snapshot of the current backupfile is taken.
#	This is done by calling a script $snapscript. 
#	Using a snapshot supporting filesystem (btrfs,xfs...) is recommended 
#	for the backupdestination. If BTRFS is used you may have a look to 
#           https://github.com/dolorosus/btrfs-snapshot-rotation
#
#	After the snapshot is taken, most of the active services are shutdown.
#	You should adapt the function *progs()* according your needs.
#
#	Also you should take a closer look to *setup()*. Change the variables according
#	your filesystem structure.
#
#
#	2019-04-30	initial commit by Dolorosus
#
#

setup () {
	#
	# Define some fancy colors only if connected to a terminal.
	# Thus output to file is no more cluttered
	#
	[ -t 1 ] && {
		RED=$(tput setaf 1)
		GREEN=$(tput setaf 2)
		YELLOW=$(tput setaf 3)
		BLUE=$(tput setaf 4)
		MAGENTA=$(tput setaf 5)
		CYAN=$(tput setaf 6)
		WHITE=$(tput setaf 7)
		RESET=$(tput setaf 9)
		BOLD=$(tput bold)
		NOATT=$(tput sgr0)
	}||{
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		MAGENTA=""
		CYAN=""
		WHITE=""
		RESET=""
		BOLD=""
		NOATT=""
	}
	MYNAME=$(basename $0)
	
	export stamp=$(date +%y%m%d_%H%M%S)
	export destvol="/media/pi/usbBack"
	export destpath="${destvol}/BACKUPS" 
	export snappath="${destvol}/.snapshots/BACKUPS"
	export destpatt="MyRaspi-1*_[0-9]*.img"
	export bcknewname="MyRaspi-${stamp}.img"
	export tmppre="\#"

	export bckscript="/home/pi/scripts/imgbck.bash"
	export snapscript="/home/pi/scripts/btrfs-snapshot-rotation.sh"
	export mark="manual"
	export versions=28
}


msg () {
	echo "${YELLOW}${1}${NOATT}"
}

errexit () {
	
	case "${1}" in
		1)	echo "${RED}You have to be root to run this script${NOATT}"
			exit ${1};;
				
		10)	echo "${RED}More than one backupfile according to ${destpath}/${destpatt} found."
			echo "Can't decide which one to use.${NOATT}"
			exit ${1};;

		11)	echo "${RED}backupfile according to ${destpath}/${destpatt} is no flatfile.${NOATT}"
			exit ${1};;

		12)	echo "${RED}backupfile according to ${destpath}/${destpatt} is empty.${NOATT}"
			exit ${1};;
        
	20)	echo "${RED}No executable file $bckscript found.${NOATT}"
			exit ${1};;

	21)	echo "${RED}No executable file $snapscript found.${NOATT}"
			exit ${1};;
			
		25)	echo "${YELLOW}${action} $prog failed${NOATT}"
			;;
			
		30) echo "${RED}something went wrong..."
			echo "the incomplete backupfile is named: ${destpath}/${tmppre}${bcknewname}"
			echo "Resolve the issue, rename the the backupfile and restart"
			echo "Good luck!${NOATT}"
			exit ${1};;
			
			*)	echo "${RED}An unknown error occured${NOATT}" 
				exit 99;;
	esac
}

progs () {

	local prog
	local action=${1:=start}

	for prog in 'mysql' 'pihole-FTL' 'lighttpd' 'syncthing@pi' 'docker' 'containerd' 'lightdm' 'log2ram'
	do
		systemctl ${action} ${prog} && {
			echo "${action} $prog successful" 
		}||{
			errexit 25
		}
	done
	[ "$action" == "start" ] && pihole restartdns 
	return 0
}

do_backup () {
	
	local creopt="${1}"
	
	progs stop

	# move the destination to a temporary filename while 
	# the backup is working
	msg "moving ${bckfile} to ${destpath}/#${bcknewname}"
	mv "${bckfile}" "${destpath}/#${bcknewname}"
	msg "starting backup_: $bckscript start ${creopt} ${destpath}/${tmppre}${bcknewname}"
	$bckscript start ${creopt} "${destpath}/#${bcknewname}" && {
		msg "moving  ${destpath}/#${bcknewname} to ${destpath}/${bcknewname}"
		mv "${destpath}/#${bcknewname}" "${destpath}/${bcknewname}"
		progs start
	}||{
		progs start
		errexit 30
	}
 
	msg "Backup successful"
	msg "Backupfile is_: ${destpath}/${bcknewname}"
	return 0
}

# ===============================================================================================================
# Main
# ===============================================================================================================

#
# Please, do not disturb
#
trap "progs start" SIGTERM SIGINT

setup

#
# Bailout in case of uncought error
#
set -e

[ $(/usr/bin/id -u) == "0" ] || errexit 1
[ "$(ls -1 ${destpath}/${destpatt}|wc -l)" == "0" ] && {
  do_backup -c
  exit 0
}

#
#	some checks 
#
[ "$(ls -1 ${destpath}/${destpatt}|wc -l)" == "1" ] || errexit 10

bckfile="$(ls -1 ${destpath}/${destpatt})" 
[ -f "${bckfile}" ] || errexit 11
[ -s "${bckfile}" ] || errexit 12

[ -x "${bckscript}" ] || errexit 20
[ -x "${snapscript}" ] || errexit 21

#
# create a snapshot of current state
#
${snapscript}  ${destpath} ${destvol}/.snapshots/BACKUPS ${mark} ${versions}

#
# Finally do the backup
#
do_backup

#
# All's Well That Ends Well
#
exit 0

