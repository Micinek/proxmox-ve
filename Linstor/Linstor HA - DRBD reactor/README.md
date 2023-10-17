# Linstor HA - DRBD Reactor

Continuing on our Linstor setup, we will create High Avability DRBD cluster on our 3 nodes using DRBD Reactor, which does not need separate Linstor controller.

DRBD Reactor will run DRBD resource with replicated database for our controller, than we will install controller on all nodes and using drbd-reactor we will have always 1 of the nodes running controller. The service will check for service always running the controller on one node.