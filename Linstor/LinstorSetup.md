# ProxmoxVE instal drbd9 with LINSTOR HA Controller

## Current version of of ProxmxoVE is 7.4.1 during making of this tutorial. Tutorial is based on 3 node setup, but can be done with only Controller + 1 node



#### First of all add licence key or add no-subscription repo and make sure it is active, if you dont have Licence Key, the file should look like this

##### You can echo > it right like is (for Proxmox 7.x.x - Debian bullseye), you need one of these repos to install pve-headers for DRBD9, Linstor needs drbd9 to work.
```
cat << EOF > /etc/apt/sources.list
deb http://ftp.cz.debian.org/debian bullseye main contrib

deb http://ftp.cz.debian.org/debian bullseye-updates main contrib

##### security updates
deb http://security.debian.org bullseye-security main contrib

deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription
EOF
```

##### Install latest kernel headers and then drbd 9. You should restart after this.
```
apt install pve-headers -y
```

##### Now we add linbit repository to our sources
```
echo "deb http://packages.linbit.com/proxmox/ proxmox-7 drbd-9" > /etc/apt/sources.list.d/linbit.list
wget -O- https://packages.linbit.com/package-signing-pubkey.asc | apt-key add -       ### if by any chance you get error here, install "gnupg gnupg2"
apt update
apt install drbd-dkms drbd-utils -y
```

##### Modprobe drbd module and check loaded vesrion
```
modprobe drbd
cat /proc/drbd
```

##### You should get version 9.x.x, my verision during making this tutorial was 9.2.3
```
apt-get -y install linstor-proxmox linstor-satellite linstor-client
systemctl start linstor-satellite
```

##### Prepare Debian 11 Container for Linstor Controller initialization, or create from GUI
```
wget http://download.proxmox.com/images/system/debian-11-standard_11.0-1_amd64.tar.gz -P /var/lib/vz/template/cache/
pct create 100 local:vztmpl/debian-11-standard_11.0-1_amd64.tar.gz \
  --hostname=linstor-controller \
  --net0=name=eth0,bridge=vmbr0,gw=192.168.0.1,ip=192.168.0.123/24
                                               ### Insert yourl local ip, that all PVE nodes can reach
```

##### Now start the container and launch console, or you can SSH into it
```
pct start 100
pct exec 100 bash
```

##### IN CONTAINER
```
apt update && apt upgade -y && apt install gnupg gnupg2 -y
```

##### Now we add linbit repository to our sources
```
echo "deb http://packages.linbit.com/proxmox/ proxmox-7 drbd-9" > /etc/apt/sources.list.d/linbit.list
wget -O- https://packages.linbit.com/package-signing-pubkey.asc | apt-key add -
apt update

apt install -y linstor-controller linstor-client

systemctl start linstor-controller.service
systemctl enable linstor-controller.service
```

##### Linstor requires configured locale. Configure locale:
```
sed -i '/en_US.UTF-8 UTF-8/ s/^### //' /etc/locale.gen
locale-gen

dpkg-reconfigure tzdata
```

#### Now when we have installed the controller and have linstor-satelite on all of our nodes, we can create a cluster (on the controller console)

##### Be careful to use the same name the nodes hostname, watch out for errors
##### the syntax is:    linstor node create <node-hostname> <node-ip-address>
```
linstor node create linstor-controller 192.168.0.123 --node-type controller
linstor node create pve1 192.168.0.10
linstor node create pve2 192.168.0.20
linstor node create pve3 192.168.0.30
```
  
##### now we should see the nodes in list command
```
linstor node list
```
```
╭──────────────────────────────────────────────────────────────────────╮
┊ Node               ┊ NodeType   ┊ Addresses                 ┊ State  ┊
╞┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╡
┊ linstor-controller ┊ CONTROLLER ┊ 192.168.0.10:3370 (PLAIN) ┊ Online ┊
┊ pve1               ┊ SATELLITE  ┊ 192.168.0.10:3366 (PLAIN) ┊ Online ┊
┊ pve2               ┊ SATELLITE  ┊ 192.168.0.20:3366 (PLAIN) ┊ Online ┊
┊ pve3               ┊ SATELLITE  ┊ 192.168.0.30:3366 (PLAIN) ┊ Online ┊
╰──────────────────────────────────────────────────────────────────────╯
```


##### Creatig storage pool on all 3 nodes, for example ZFS pool with created dataset for linstor  "fast/linstor"
##### linstor storage-pool create "storage backend type" "node" "name of new pool" "stogage resource"
```
linstor storage-pool create zfs pve1 zfs_pool fast/linstor
linstor storage-pool create zfs pve2 zfs_pool fast/linstor
linstor storage-pool create zfs pve2 zfs_pool fast/linstor
```
### Refer to manual for more info on diferent storage backends https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/###s-storage_pools

  
##### We have LINSTOR 3 node cluster with backend for replicating storage, now we need to create resource group for our VM images, etc.
##### Refer to manual for more options in creatin resource groups and definitions, here we will create example resource group with placing resources on only 2 nodes

##### We already have <zfs_pool> pool
```
linstor resource-group create images --storage-pool zfs_pool --place-count 2    ### creating resource group with number of placements, if you have only 1 node setup use "1"
linstor resource-group drbd-options --verify-alg crc32c images
linstor volume-group create drbdzfs      ### Creating volume group on top of resource-group, here our resources (VM drives, etc) get placed
```

##### You can also exclude node from placing any resources to it, for example a tie-breaker node
#####   linstor node set-property <node_name> AutoplaceTarget false

##### And finaly you need to add the resource group to your /etc/pve/storage.cfg file to use the storage in GUI ( here the linstor-proxmox package does the job)
##### Add this to your config file, change accorging node names and resource group names, etc.
```
drbd: drbdzfs
        content images,rootdir
        controller pve1,pve2,pve3
        resourcegroup drbdzfs
```
  
##### Be carefull to use right spacing and characters, proxmox configs are sensitive...



##### From now on if you add VM disk, Linstor will add resources to config, will setup DRBD resources and start synchronizing.
##### Also DRBD will automaticly switch "Primary" resource on node which the VM is running on, to prevent writes on the other nodes
```
╭──────────────────────────────────────────────────────────────────────────────╮
┊ ResourceName ┊ Node ┊ Port ┊ Usage  ┊ Conns ┊    State ┊ CreatedOn           ┊
╞══════════════════════════════════════════════════════════════════════════════╡
┊ resource1    ┊ pve1 ┊ 7002 ┊ InUse  ┊ Ok    ┊ UpToDate ┊ 2023-04-18 09:31:28 ┊
┊ resource1    ┊ pve2 ┊ 7002 ┊ Unused ┊ Ok    ┊ UpToDate ┊ 2023-04-18 09:31:28 ┊
┊ resource1    ┊ pve3 ┊ 7002 ┊ Unused ┊ Ok    ┊ UpToDate ┊ 2023-04-18 09:31:28 ┊
╰──────────────────────────────────────────────────────────────────────────────╯
```
