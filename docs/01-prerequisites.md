KVM-QEMU Ansible Prerequisites
==============================


A KVM Cluster consists a set of nodes with VT-d virtualization extensions
enabled allowing for the installation of a KVM Hypervisor and **libvirtd** for
VM orchestration.  A management node (any node in cluster or otherwise) is used
to deploy, configure, and manage VMs.  The management node must be configured 
with an account that has SSH key-based login with sudo rights to all nodes.
This is used both for running the Ansible playbooks and KVM Management.

This document covers the prerequisites needed for deploying a KVM cluster.


## Virtualization Extensions

VT-d enabled in the BIOS results in the **vmx** extension existing in cpu 
features. Ensure this extension is enabled for all nodes.
```sh
lscpu | grep vmx
```

Kernel options for *intel_iommu* should be enabled. The libvirt tool called 
`virt-host-validate` can be used to verify platform settings including the 
*iommu* setting. For Ubuntu systems, edit */etc/default/grub* to add the string 
*intel_iommu=on* to the **GRUB_CMDLINE_LINUX_DEFAULT** option and run 
`sudo update-grub` to affect the change.


## Configuring Storage

  The Ansible configuration provides for two storage options to the cluster.
The first is the *Primary* storage pool used to store VM's local to a given
node. Ideally, we make use of local attached disks in a *RAID10* or *RAID5*
configuration. Technically, any form of underlying storage can be used, but 
using local or direct-attached storage is best for performance. The primary 
storage pool is used as the **default** storage pool for new VM's. 

  Optionally, a *secondary* storage pool can be configured as an NFS mount 
shared across all nodes that can be used to store source/template VMs, snapshots
and clones. This pattern utilizes a *golden image* to act as the source VM, 
which is discussed further in the *Operations* document.  

  The provided Ansible will configure the NFS Server and mounts accordingly,
but relies on the system storage devices to already exist. The default
example uses a local data volume mount for all nodes  of */data01* making
*/data01/primary* the location of our default storage pool. It is important
that the same path is used across all nodes, which is then provided to Ansible.

  Again, these volumes should already exist and be mounted to the nodes prior
to running the playbooks.


## Networking

The cluster uses bridged networking for exposing VMs on the host network. The 
management server provides both DHCP static assignment of VM IPs and DNS, 
discussed in a later section.  As a result, all nodes should use the management 
server(s) for DNS.  Configuring the bridge network **br0** for *libvirt* involves 
moving the hosts primary IP Address to the bridge interface, so care should be 
taken with the below network configurations. It is highly advisable to ensure 
proper console access is available, as mistakes can render the node unreachable.

Disable the use of NetworkManager on all cluster nodes:
```sh
clush -a 'sudo systemctl stop NetworkManager'
clush -a 'sudo systemctl disable NetworkManager'
```

### Redhat-based distributions:

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

The ethernet interface is configured to use the bridge. In this case, the host 
is using a bonded Ethernet interface:
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

Once Networking and Storage are configured, the KVM stack can be deployed
via Ansible as described in the next [document](02-kvm-ansible.md).


## Ansible requirements 

Ansible should be the only package requirement needed for running the 
playbooks, which in turn installs the required KVM related packages as 
defined by *roles/kvm-qemu/vars/main.yml*. The playbooks currently target, 
and have been tested against, RHEL/CentOS 7+ and Ubuntu 22.04+ using 
Ansible version 8.5.0.
```bash
sudo apt install python3-pip python3-venv
python3 -m venv pyansible
source pyansible/bin/activate
pip install ansible==8.5.0
```


## Management plane

The preferred architecture involves having a pair of master nodes that 
serve as the management plane for the cluster. A master node would be 
used up front to bootstrap the cluster by running the necessary Ansible 
playbooks, and as such, requires SSH key access to all nodes. A pair of 
master hosts would serve as Primary and Secondary DNS to the cluster and 
as DHCP Servers, in addition to other services needed, eg. ntp, nfs,
http-based repositories, etc.


## KVM Role Account

A good practice is to use a *role* account as the user with access rights to 
manage KVM hosts. Just as with Ansible, the *kvm-mgr* tool requires ssh key 
access to all nodes. There is no need to use the *root* accout for creating 
and managing KVM.
