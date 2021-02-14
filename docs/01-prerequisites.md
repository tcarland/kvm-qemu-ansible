KVM-QEMU Ansible Prerequisites
==============================


A KVM Cluster consists a set of nodes with VT-d virtualization extensions
enabled allowing for the installation of a KVM Hypervisor and **libvirtd** for
VM orchestration.  A management node (any node in cluster or otherwise) is used
to deploy, configure, and manage VMs using SSH. Thus, the management node must
be configured with an account that has SSH key-based login with password-less
sudo rights. This is used both for running Ansible playbooks and KVM Management.

This document covers the prerequisites needed for deploying a KVM cluster.

## Virtualization Extensions
VT-d enabled in the BIOS results in the **vmx** extension existing in cpu 
features. Ensure this extension is enabled for all nodes.
```
lscpu | grep vmx
```

## Configuring Storage

  The Ansible configuration accounts for two storage options to the cluster.
The first is the *Primary* storage pool used to store VM's local to a given
node. Ideally, we make use of local attached disks in a *RAID10* or *RAID5*
configuration. Technically, any form of underlying storage can be used, but 
using local storage is better for performance. The primary storage pool is 
used as the *default* storage pool for creating VM's on a given node.

  Additionally, an optional *secondary* storage can be configured as a NFS
mount shared across all nodes that would be used to store source VMs, snapshots
and/or clones. The pattern provided utilizes a *golden image* to act as the
source vm, which is discussed in *operations* document.  

  The provided Ansible will configure the NFS Server and mounts accordingly,
but relies on the system storage devices to already exist. The default
example uses a local data volume mount for all nodes  of */data01* making
*/data01/primary* the location of our default storage pool. It is important
that the same path is used across all nodes, which is also deployed by Ansible.

  Again, these volumes should already exist and be mounted to the nodes prior
to running Ansible.


## Networking

  Networking in the cluster uses bridged networking for exposing all
configured VMs on the local host network.  The management server provides both
DHCP static assignment of VM IPs and DNS, discussed in a later section.  As a
result all nodes should use management server for DNS.  Configuring the bridge
network **br0** for libvirt involves moving the hosts primary IP to the actual
bridge interface, so care should be taken with the below configuration and it
is highly recommended to ensure proper console access is available as mistakes
will render the node unreachable.

Disable the use of NetworkManager on our cluster nodes:
```
clush -a 'sudo systemctl stop NetworkManager'
clush -a 'sudo systemctl disable NetworkManager'
```

Configure *ifcfg-br0* in `/etc/sysconfig/network-scripts/` for CentOS/RHEL:
```
$ cat ifcfg-br0
DEVICE=br0
TYPE=Bridge
BOOTPROTO=none
ONBOOT=yes
DELAY=0
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPADDR=172.30.10.41
PREFIX=24
GATEWAY=172.30.10.1
DNS1=172.30.10.11
DNS2=172.30.10.12
```

Ethernet interface is configured to use the Bridge. In this case, the host is
using a bonded Ethernet interface:
```
$ cat ifcfg-bond0
TYPE=Bond
NAME=bond0
DEVICE=bond0
BONDING_OPTS="miimon=100 updelay=0 downdelay=0 mode=802.3ad xmit_hash_policy=1"
BONDING_MASTER=yes
MTU=9000
ONBOOT=yes
BRIDGE=br0
```

Once Networking and Storage are configured, we can install KVM via Ansible
described in the next readme.


## Ansible requirements 

Ansible should be the only package requirement needed for running the 
playbooks, which in turn installs the required KVM related packages as 
defined by *roles/kvm-qemu/vars/main.yml*. The playbooks currently target and 
have been tested against RHEL/CentOS 7 and Ubuntu 20.04 Focal using 
Ansible version 2.9. 

## Management plane

Preferred architecture involves having a pair of master nodes that 
serve as the management plane for the cluster. A master node would be 
used up front to bootstrap the cluster by running the necessary Ansible 
playbooks, and as such, requires SSH key access to all nodes. 

## KVM Role Account

Best practice is to use a role-account as the user with access rights to 
manage KVM hosts. Just as in Ansible, the mgmt tool requires ssh hostkey 
access to all nodes. There is no need to use 'root' for managing virtual 
machines.