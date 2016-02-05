#!/bin/bash

# backs up VMware Workstation shared VMs.
# This script scans the VMware Shared VMs folder looking
# for a "vmbackup.conf" file inside. If found,
# determines that the virtual machine has a backup plan according
# to that .conf file.
# It will check the plan and if it is time to back it up, 
# it will stop it gracefully, make a copy, compress it,
# delete the copy and upload the compressed files to a backup FTP
# location

# Default settings are stored in /etc/vmbackup.conf


CONFIG_FILE="/etc/vmbackup.conf"
AUTHOR="Javier Peletier <jm@epiclabs.io>"
LICENSE="Released under GPL. All rights reserved. Epic Labs, S.L. 2016 http://epiclabs.io"

function log {

local T=`date "+%Y-%m-%d %H:%M:%S"`
echo $T - $1 $2 $3
}

# Reads a configuration file of the format VARIABLE=VALUE
function readConfig {

	shopt -s extglob
	while IFS='= ' read lhs rhs
	do
		if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
			rhs="${rhs%%\#*}"    # Del in line right comments
			rhs="${rhs%%*( )}"   # Del trailing spaces
			rhs="${rhs%\"*}"     # Del opening string quotes 
			rhs="${rhs#\"*}"     # Del closing string quotes 
			printf -v "$lhs" "$rhs"
		fi
	done < "$1"

}

function writeTimestampFile { # sequence number, timestamp, timestamp file

	echo "SEQNUM=$1" > "$3"
	echo "TIMESTAMP=$2" >> "$3"

}

function backup {

	readConfig "$VMWARE_SHAREDVM_PATH/$1/vmbackup.conf"
	log "Processing VM $VM_NAME..."
	
	VM_FOLDER=$1
	VMX_FILE="$VM_NAME.vmx"
	VM_FOLDER_FULL_PATH="$VMWARE_SHAREDVM_PATH/$VM_FOLDER"
	VMX_FULL_PATH="$VM_FOLDER_FULL_PATH/$VMX_FILE"
	VMBACKUP_TIMESTAMP_FILE="$VMBACKUP_LOG_FOLDER/$VM_NAME.timestamp"
	TEMP_DIR="$BACKUP_TEMP_FOLDER/$VM_NAME.backup.d"
	
	if [ ! -f "$VMX_FULL_PATH" ]; then
		log "Cannot find $VMX_FULL_PATH!!"
		return 1
	fi

	#check if the timestamp file exists
	if [ ! -f "$VMBACKUP_TIMESTAMP_FILE" ]; then
		writeTimestampFile 0 0 "$VMBACKUP_TIMESTAMP_FILE"
	fi
	
	#obtain sequence number to use
	readConfig "$VMBACKUP_TIMESTAMP_FILE"

	if (( NOW < TIMESTAMP )) ; then
		log "Backing up '$VM_NAME' skipped. Not the time to back it up yet..."
		return 1
	fi
	

	if [ -d "$TEMP_DIR" ]; then
		rm -r "$TEMP_DIR"
	fi
	
	mkdir "$TEMP_DIR"
	mkdir "$TEMP_DIR/$VM_NAME"

	log "Querying status of $VM_NAME..."
	vmrun list | grep "$VMX_FULL_PATH" > /dev/null
	VM_OFF=$?

	if [ $VM_OFF -eq 0 ]; then
		log "$VM_NAME is running. Shutting it down..."
		vmrun -T ws-shared -u "$VMBACKUP_USER" -p "$VMBACKUP_PASSWORD" -h $VMWARE_HOST stop "[ha-datacenter/standard] $VM_FOLDER/$VMX_FILE" soft nogui
	else
		log "$VM_NAME is not running."
	fi
		
	log "copying $VM_NAME files to temporary folder $TEMP_DIR/..."

	cp -r "$VM_FOLDER_FULL_PATH" "$TEMP_DIR/"


	log "VM copied."
	if [ $VM_OFF -eq 0 ]; then
		log "Restarting $VM_NAME..."
		vmrun -T ws-shared -u "$VMBACKUP_USER" -p "$VMBACKUP_PASSWORD" -h $VMWARE_HOST start "[ha-datacenter/standard] $VM_FOLDER/$VMX_FILE" nogui
	fi


	BACKUP_FOLDER_NAME=$VM_NAME-$SEQNUM
	BACKUP_FOLDER_FULL_PATH=$TEMP_DIR/$BACKUP_FOLDER_NAME
	ZIP_FILE_FULL_PATH=$BACKUP_FOLDER_FULL_PATH/$VM_NAME.7z

	log "Compressing $VM_NAME backup..."
	7z a -t7z $ZIP_FILE_FULL_PATH -m0=lzma2 -mx=9 -aoa -v256m -r "$TEMP_DIR/$VM_FOLDER"

	BACKUP_REMOTE_FOLDER=$FTP_REMOTE_FOLDER/$BACKUP_FOLDER_NAME

	FTP_COMMAND="open -u $FTP_USER,$FTP_PASSWORD $FTP_HOSTNAME"
	FTP_COMMAND="$FTP_COMMAND;mirror -R --verbose --delete-first --delete $BACKUP_FOLDER_FULL_PATH/ $BACKUP_REMOTE_FOLDER"

	log "Uploading backup of $VM_NAME to $FTP_HOSTNAME ..."	
	lftp -c "$FTP_COMMAND"
	rm -r "$TEMP_DIR"

	TIMESTAMP=$((NOW + BACKUP_PERIOD * 24 * 60 * 60 - 3600)) # schedule for 1h before to ensure it triggers
	SEQNUM=$(((SEQNUM+1) % NUMBACKUPS ))
	writeTimestampFile "$SEQNUM" "$TIMESTAMP" "$VMBACKUP_TIMESTAMP_FILE"
	
	log "Finished backing up $VM_NAME"
}

log "VMware backup script, by $AUTHOR"
log "$LICENSE"
log ----------------

NOW=`date +%s`

log "Reading configuration file $CONFIG_FILE ..."
readConfig "$CONFIG_FILE"

if [ ! -d "$VMBACKUP_LOG_FOLDER" ]; then
	mkdir "$VMBACKUP_LOG_FOLDER"
fi

N=$(((NOW / 86400) % 7 )) 
LOGFILE="$VMBACKUP_LOG_FOLDER/log-$N.txt"

log "Logging to $LOGFILE."
log "Now scanning for VMs..."
for d in "$VMWARE_SHAREDVM_PATH"/*/ ; do 
	if [ -f "$d"vmbackup.conf ]; then
		backup `basename "$d"` >> "$LOGFILE"
		readConfig "$CONFIG_FILE"
	fi

done

log "Done."

