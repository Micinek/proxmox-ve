#!/bin/bash

# Check for pv availability
if ! command -v pv >/dev/null 2>&1; then
  echo "pv command not found. Installing..."
  # Use sudo for package installation (assuming you have root or sudo privileges)
  sudo apt update
  sudo apt install pv
else
  echo "pv command found. Proceeding..."
fi

# Check for screen and tmux availability
screen_available=$(command -v screen >/dev/null 2>&1; echo $?)
tmux_available=$(command -v tmux >/dev/null 2>&1; echo $?)

# Check for screen session (more reliable method)
if [ -z "$TMUX" -a -z "$STY" ]; then
  if [ $screen_available -eq 0 -o $tmux_available -eq 0 ]; then
    echo "Warning: This script is recommended to be run within a screen session (if available) to avoid interruptions."
    echo "Consider starting a screen session before running this script again."
  else
    echo "Warning: This script is recommended to be run within a terminal multiplexer (like screen or tmux) to avoid interruptions."
    echo "Consider installing 'screen' or 'tmux' for session management."
  fi
  exit 1
fi

# Get user input
read -p "Enter source pool name: " source_pool
read -p "Enter source dataset name: " source_dataset
read -p "Enter destination hostname or IP: " destination_host
read -p "Enter destination pool name: " destination_pool
destination_dataset="$destination_pool/$source_dataset"

# Function to create a temporary snapshot
create_temp_snapshot() {
  snapshot_name="temp_$(date +%Y-%m-%dT%H:%M:%S)"
  zfs snapshot $source_pool/$source_dataset@$snapshot_name
  echo "Created temporary snapshot: $source_pool/$source_dataset@$snapshot_name"
}

# Check SSH connectivity with the destination host
if ! ssh -o ConnectTimeout=5 $destination_host exit; then
  echo "Error: SSH connection to $destination_host failed."
  echo "Consider adding your SSH key to the remote host for passwordless access."
  echo "Refer to instructions on setting up SSH key-based authentication for ZFS send/recv."
  exit 1
fi


echo "Performing full ZFS send..."
create_temp_snapshot
zfs send -R $source_pool/$source_dataset@$snapshot_name | pv | ssh $destination_host "zfs recv -dFu $destination_dataset"


# Cleanup temporary snapshot (uncomment if the function is used)
if [ -n "$snapshot_name" ] && [[ "$snapshot_name" == temp_* ]]; then
  echo "Cleaning up temporary snapshot..."
  zfs destroy $source_pool/$source_dataset@$snapshot_name
fi

echo "Snapshot transfer complete."
