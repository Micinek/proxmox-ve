### shows dataset snapshots with settings for auto-snapshots and inheritance
zfs get -r com.sun:auto-snapshot tank

### or you can use this to exclude the snapshots from results, and show only datasets and their inheritance
zfs get -r com.sun:auto-snapshot tank | grep -v "@zfs-auto-snap"


### turns on auto-snapshots on specified dataset and its children (unless children are set differently by the same command)
zfs set com.sun:auto-snapshot=true tank

### now we set true / false on auto-snapshot type (frequent, hourly, daily, weekly, monthly)
zfs set com.sun:auto-snapshot:monthly=false tank/fileshare
zfs set com.sun:auto-snapshot:weekly=false tank/fileshare
zfs set com.sun:auto-snapshot:daily=true tank/fileshare
zfs set com.sun:auto-snapshot:hourly=false tank/fileshare
zfs set com.sun:auto-snapshot:frequent=false tank/fileshare

### managing snapshot retention is done in /etc/cron.....  files, changing the "keep" option in those files applies settings on next run of the command




## removing old or unwanted snapshots

### show all snapshots on specified dataset
zfs list -t snapshot tank/fileshare -o name | grep "zfs-auto-snap"

### or all snapshots on the whole pool
zfs list -r -t snapshot tank -o name | grep "zfs-auto-snap"


### this command is "dry run" for deleting snapshots, lists snapshots in the dataset with these parameters
### you know what "grep" does...
### "tac" reverses list, so it shows snapshots from newest
### "tail -n +10" does not show 10 latest results, only older - so you will KEEP the nuber of snapshots you write in this number
### xargs -n 1 echo          does echo for each of the lines (snapshot names)

zfs list -t snapshot tank/fileshare -o name | grep "zfs-auto-snap" | tac | tail -n +10 | xargs -n 1 echo

### a little variation of previous command does IRREVERSIBLE removal of the snapshots we listed earlier as "dry run", and prints deleted snapshots with -v at the end
### xargs -n 1 zfs destroy -v          does echo for each of the lines (snapshot names)
zfs list -t snapshot tank/fileshare -o name | grep "zfs-auto-snap" | tac | tail -n +10 | xargs -n 1 zfs destroy -v

