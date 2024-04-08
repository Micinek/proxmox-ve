#!/bin/bash

# Source server address
server="192.168.xxx.xxx"

# Array of folders to mount
folders=(
    "media"
    "photos"
    "dokuments"
)

# Mount point prefix (replace with your desired prefix), folder where we will mount NFS mounts to copy from
mount_point_prefix="/synology"

# NFS mount prefix for Synology and other NAS systems, if not needed, leave empty or change accordingly
nfs_prefix=volume1

# Loop through each folder in the array
for folder in "${folders[@]}"; do
  # Construct the mount point path
  mount_point="$mount_point_prefix/$folder"

  # Create the mount point directory if it doesn't exist
  if [ ! -d "$mount_point" ]; then
    mkdir -p "$mount_point"
    echo "Created mount point directory: $mount_point"
  fi

  # Check if the folder is already mounted
  if mountpoint -q "$mount_point"; then
    echo "$folder is already mounted at $mount_point"
  else
    # Mount the folders using NFS   ( RO = read only, we dont need, nor we want our backup server to accidentaly write something to live data)
    mount -t nfs -o ro,rsize=8192 $server:/$nfs_prefix/$folder $mount_point

    # Check the mount status (optional)
    if [ $? -eq 0 ]; then
      echo "Successfully mounted $folder to $mount_point"
    else
      echo "Failed to mount $folder"
    fi
  fi
done

# Local folder we will backup to, mine is ZFS pool TANK with dataset ARCHIVE
loc_folder="/tank/archive"

# log file to store our changes during incremental transfers and send them via email ( first logs will contain all files transfered, lot of lines )
log_file="/root/rsync/rsync.log"

# clean up log file before starting backup and filling with new data
echo "" > "$log_file"

# Email configuration
recipient="EMAIL RECIPIENT"
subject="Backup Report - Rsync log"
from="EMAIL SENDER"

# this function sends email with contents of log file, you will need to install and configure smtp if you do not have already
function mail_rep {
ssmtp "$recipient" <<EOF
Subject: "$1"
From: $from
$(cat $log_file)
EOF
}

for folder in "${folders[@]}"; do
    echo "------------------START "$folder"------------------------" >> $log_file
    rsync -avz --itemize-changes --log-file=$log_file --exclude="#recycle/" --exclude="#snapshot/" $mount_point_prefix/$folder/ $loc_folder/$folder/
    echo "-------------------END  "$folder"------------------------" >> $log_file
    echo ""
    echo ""
done

email_subject="RSync completed from SynologyNAS to BackupServer"
mail_rep "$email_subject"
