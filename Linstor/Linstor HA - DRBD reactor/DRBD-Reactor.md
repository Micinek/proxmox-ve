# We need to install the linstor controller and client on all of our nodes.
apt-get update && apt install -y linstor-controller linstor-client


# Disable the service on all nodes so it does not auto-start, this will be managed by drbd.reactor
systemctl disable linstor-controller.service
systemctl stop linstor-controller.service


# Configure HA storage for linstor roaming controller
# You will need at least 2 nodes to create resource

linstor resource-definition create linstor_db
linstor resource-definition drbd-options --on-no-quorum=io-error linstor_db
linstor resource-definition drbd-options --auto-promote=no linstor_db
linstor volume-definition create linstor_db 200M
linstor resource create linstor_db -s zfs_pool --auto-place 3
# In last command replace "zfs_pool" with your pool name which we created in previous guide

# Now disable the service on our separate Linstor Controller container
systemctl stop --now linstor-controller

# Create service from which we will mount the HA resource containing the Linstor Database
# Repeat this step on every node
cat << EOF > /etc/systemd/system/var-lib-linstor.mount
[Unit]
Description=Filesystem for the LINSTOR controller

[Mount]
What=/dev/drbd/by-res/linstor_db/0
Where=/var/lib/linstor
EOF
# you can use the alternate link like /dev/drbdXX or the udev symlink


# Create new folder which we are gonna use as mount point for HA resource. Repeat this step on every node.
mkdir /var/lib/linstor

# We need to activate the resource on one of the nodes, so we can work with the data on resource.
drbdadm primary linstor_db

# Now we need to create filesystem on the drbd resource (for our database folder)
mkfs.ext4 /dev/drbd/by-res/linstor_db/0
systemctl start var-lib-linstor.mount
cp -r /var/lib/linstor.orig/* /var/lib/linstor
systemctl start linstor-controller





# Repeat following steps on every node


# Now we want to install required package for drbd HA setup, and restart + enable the service
apt install drbd-reactor

# Create config file for drbd-reactor
cat << EOF > //etc/drbd-reactor.d/linstor_db.toml
[[promoter]]
id = "linstor_db"
[promoter.resources.linstor_db]
start = ["var-lib-linstor.mount", "linstor-controller.service"]
EOF

systemctl restart drbd-reactor
systemctl enable drbd-reactor

# Check for errors in the service
systemctl status drbd-reactor

# Now we need to edit the linstor-satelite service to NOT delete the resource file for linstor controller DB at startup
systemctl edit linstor-satellite
# Add this to end of file
[Service]
Environment=LS_KEEP_RES=linstor_db
# And restart the service
systemctl restart linstor-satellite


# Now we need to tell linstor where avalible controllers could be, so we can use linstor commands on each node
mkdir /etc/linstor
cat << EOF > /etc/linstor/linstor-client.conf
[global]
controllers=pve1,pve2,pve3
EOF
# Use your hostnames or fixed IP addresses for controller pointers.

# Last part of the process is removing the old controller from container.
linstor node delete linstor-controller

# When you list your nodes, you should see only your nodes. You can disable or delete the container.



# Now you should have HA DRBD setup with Linstor controller. Where controller is always running.