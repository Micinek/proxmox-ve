#!/bin/bash

# Get a list of ZFS datasets excluding 'rpool' and 'subvol'
datasets=$(zfs list -t filesystem -o name 2> zfs_error.log | grep -v 'rpool' | grep -v 'subvol' | grep -v 'NAME')

# Create an array for whiptail menu
options=()
for dataset in $datasets; do
    options+=("$dataset" "" off)
done

# Use whiptail to create a menu and store the selected datasets in a variable
selected_datasets=$(whiptail --title "ZFS Dataset Selection" --separate-output --checklist "Select datasets to show snapshots:" 25 40 15 "${options[@]}" 3>&1 1>&2 2>&3)


if [ $? -ne 0 ]; then
    echo "Error occurred during the last command. DATASET"
    exit 1
fi

selected_snapshots=()

for selected_dataset in $selected_datasets; do
    snapshots=$(zfs list -t snapshot -o name -r "$selected_dataset" | awk '{print $1}' | grep -v '@$' | grep -v 'NAME')
....
    if [ -n "$snapshots" ]; then
        # Append snapshots to the array
        selected_snapshots+=($snapshots)
    else
        echo "No snapshots found for dataset: $selected_dataset"
    fi
done

# Create an array for whiptail menu
snapshot_options=()
for snapshot in "${selected_snapshots[@]}"; do
    snapshot_options+=("$snapshot" "" off)
done

while true; do
    # ... (previous code remains unchanged)

    # Use whiptail to create a menu and store the selected snapshots in a variable
    selected_snapshots=$(whiptail --title "ZFS Snapshot Selection" --separate-output --checklist "Select Snapshots to delete:" 40 80 35 "${snapshot_options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "Error occurred during the last command. SNAPSHOT"
        exit 1
    elif [ -z "$selected_snapshots" ]; then
        echo "No snapshots selected. SNAPSHOT"
        exit 1
    fi

    # Display selected snapshots in a table for confirmation
    whiptail --title "Selected Snapshots Confirmation" --yesno "Selected snapshots:\n\n$selected_snapshots\n\nIs this correct?" 20 60

    # Check the exit status of the confirmation whiptail command
    if [ $? -eq 0 ]; then
        # User confirmed, break out of the loop and proceed
        break
    else
        # User said NO, go back to select snapshots
        continue
    fi
done

# If user confirms, proceed with echoing the selected snapshots
echo "Selected snapshots:"
for selected_snapshot in $selected_snapshots; do
    echo "$selected_snapshot"
done
