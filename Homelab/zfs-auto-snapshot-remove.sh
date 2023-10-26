#!/bin/bash

echo "----------------------------------"
echo "Here is a list of all zfs datasets (and lxc mount points)"
echo "----------------------------------"
zfs list -t filesystem -H -o name | grep -v 'subvol'

while true; do
    read -p "Please insert the dataset to search for snapshots (or 'q' to quit): " search_dataset

    if [ "$search_dataset" == "q" ]; then
        echo "Exiting the script."
        break
    fi

    if zfs list -r -t snapshot "$search_dataset" &>/dev/null; then
        echo "Snapshots in dataset '$search_dataset':"
        zfs list -r -t snapshot "$search_dataset" -o name | grep "zfs-auto-snap"

        while true; do
            echo "-----------------------------------------------------------------------"
            read -p "How many snapshots you want to KEEP? Keep 'xx' of LATEST snapshots ('b' for going back to snapshot searching or 'q' to quit): " keep_count
            echo "-----------------------------------------------------------------------"

            if [ "$keep_count" == "q" ]; then
                echo "Exiting the script."
                exit 0

            elif [ "$keep_count" == "b" ]; then
                break

            elif [[ "$user_input" =~ ^[0-9]+$ ]]; then
                echo "-----------------------------------------------------------------------"
                echo "-------------BE CAREFUL, THIS DESTROY COMMAND IS PERMANENT-------------"
                echo "-----------------------------------------------------------------------"
                echo "SANITY CHECK, the following snapshots will be deleted "
                zfs list -t snapshot "$search_dataset" -o name | grep "zfs-auto-snap" | tac | tail -n +$((keep_count + 1))

            else
                echo "That is not a valid answer, try again."
                break
            fi

            read -p "Are you sure you want to delete these snapshots? (yes/no): " confirm
            if [ "$confirm" == "yes" ]; then
                zfs list -t snapshot "$search_dataset" -o name | grep "zfs-auto-snap" | tac | tail -n +$((keep_count + 1)) | xargs -n 1 zfs destroy -r
                echo "Snapshots have been deleted."

            elif [ "$keep_count" == "q" ]; then
                echo "Exiting the script."
                exit 0

            else
                echo "Not deleting any snapshots. Going back to snapshot searching"
            fi
        done
    else
        echo "Dataset '$search_dataset' not found or has no snapshots."
    fi
done

