kvm-qemu-ansible
=================

 Ansible playbook for installing KVM-QEMU on either RHEL/Centos or Ubuntu
Linux systems. This is intended for deploying KVM across a cluster of nodes.
The Ansible doesn't configure any primary storage pools, but there are NFS
roles for utilizing NFS as a secondary storage pool.


## KVM Setup

  Once Ansible has been run, all hosts should be configured with a KVM
Hypervisor and an NFS share. The ansible does not, however, configure
any storage pools or networking on the nodes.  The following sections
discuss configuring KVM for use across a cluster by configuring Bridged
Networking for the nodes and Storage pools.

  Additionally, there are two management scripts provided for managing
Virtual Machines across the infrastructure.

- **kvmsh**:  This tool primarily wraps the usage of libvirt related tools
such as 'virsh', 'virt-install', and 'virt-clone'. It utilizes the same
command structure as 'virsh', but provides the ability to perform the
additional install and cloning steps along with some sane defaults to
use in a clustered setup. This tool is primarily run on an individual host
to manipulate the VMs on that given host.

- **kvm-mgr.sh**:  A script for managing VMs across a cluster from a
single management node. Relying on SSH host keys, the tool takes a manifest
describing the VM configurations and utilizes *kvmsh* per node to implement
various actions like create, start, stop, and delete.

  The inventory for KVM hosts is a JSON Manifest of the following schema:
```
[
    {
      "host" : "sm-01",
      "vmspecs" : [
        {
          "name" : "kvmhost01",
          "hostname" : "kvmhost01.chnet.internal",
          "ipaddress" : "10.10.5.11",
          "vcpus" : 2,
          "memoryGb" : 4,
          "maxMemoryGb" : 8,
          "numDisks": 0,
          "diskSize" : 0
        }
      ]
    }
]
```

### Requirements

The requirements for running the tools are:
 - A management node (like the ansible server used to deploy) for running
   *kvm-mgr.sh* using SSH Host Keys.
 - `clustershell` for running 'kvmsh' across nodes is highly recommended.
 - The 'kvmsh' utility to be distributed to all nodes and placed in the
   system path.
 - DnsMasq should be installed on the management node where 'kvm-mgr.sh' is
 run from. This is used to provide DNS configuration and Static IP
 assignments for the cluster via DHCP.

```
clush -g lab --copy kvmsh
clush -g lab 'sudo cp kvmsh /usr/local/bin'
clush -g lab 'rm kvmsh'
```

#### DnsMasq

  The user running the kvm-mgr.sh script should have sudo rights with NOPASSWD set.
The script will automatically configure the DHCP static lease based on the
provided manifest. The ansible already install and configures DnsMasq as a
part of the `mgmt-server` role.

### Storage Pools

  For a first time install, we must define our Storage Pools. We want the VM's
to run from local disk, but we also define a NFS share as our *Secondary*
storage:
```
# default pool is our local, primary storage pool
clush -B -g lab 'virsh --connect qemu:///system pool-define-as default dir - - - - "/data01/primary"'

# secondary storage pool is our nfs share
clush -B -g lab 'virsh --connect qemu:///system pool-define-as secondary dir - - - - "/secondary"'

# build pools
clush -B -g lab 'virsh --connect qemu:///system pool-build default'
clush -B -g lab 'virsh --connect qemu:///system pool-build secondary'

# start pools :  pools may have already started (if dir already exists)
clush -B -g lab 'virsh --connect qemu:///system pool-start default'
clush -B -g lab 'virsh --connect qemu:///system pool-start secondary'

# set autostart on primary 'default' pool
clush -B -g lab 'virsh --connect qemu:///system pool-autostart default'

# show results
clush -B -g lab 'virsh --connect qemu:///system pool-list --all'
# or using our kvmsh tool
clush -B -g lab 'kvmsh pool-list'
```

### Networking

  The *kvm-qemu* role does **not** configure the networking component of
setting up the host bridge `br0`. This should be done ahead of time, carefully
or with proper console access.

Disable the use of NetworkManager on our cluster nodes:
```
clush -a 'sudo systemctl stop NetworkManager'
clush -a 'sudo systemctl disable NetworkManager'
```

Configure *ifcfg-br0* in `/etc/sysconfig/network-scripts/`
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
using a bonded ethernet interface:
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

### Create a Base Image

The build script, `kvm-mgr.sh`, relies on a base VM image to use when building
the VM's. This base images is used across all nodes to build the environment. By
default, the scripts use a Centos7 ISO as source iso when creating VMs from
scratch, but other ISO's can be provided by the `--image` command option.

Since the resulting base VM will be cloned by all nodes when building VM, the
VM should be created on the Secondary Storage pool (NFS) to make it automatically
available to all hosts.

When creating a new VM, the `kvmsh` script looks for the source ISO in a path
relative to storage pool in use, we ensure the ISO is also stored in the Secondary
pool.
```
ssh sm-01 'ls -l /secondary'
total 2525812
-rw-r--r--. 1 root idps   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-1908.iso
```

The first VM can then be created from any node and pointed to the secondary pool.
```
$ kvmsh --pool secondary --console create centos7
```

This will attach to the console of the new VM to provide access to the
ISO installer.  Note that the networking interface should be set to start
at boot with DHCP. Once complete, the VM will exist in our secondary pool:
```
$ ls -l /secondary
-rw-r--r--. 1 root root 42949672960 Apr 27 13:12 centos7-vda.img
-rw-r--r--. 1 root idps   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-1908.iso
```

Another example uing a larger boot disk (default is 40G)
```
$ kvmsh --pool secondary --bootsize 80 --console create centos7-80
```

Once installed, we can add some additional base requirements that we need
across our environment. Most importantly, creating any role or user account(s)
with the correct SSH key(s) and configuring the resolvers to point to our
internal DNS Server configured on the Management Node. This list provides
these and some other items worth configuring into the base image:
 - set the resolvers to dnsmasq server
 - configure ssh keys
 - visudo, set NOPASSWD for the wheel or sudo group
 - disable firewalld if desired.
 - disable selinux if desired

Once complete, the final step would be to stop the VM and acquire the
XML Definition for use across all remaining nodes to define our source VM.

```
$ kvmsh stop centos7
$ kvmsh dumpxml centos7 > centos7.xml

$ clush -a --copy centos7.xml
$ clush -a 'kvmsh define centos7.xml
```

### Building VMs

 Building the environment is accomplished by providing the JSON manifest to the
`kvm-mgr.sh` script.
```
$ ./bin/kvm-mgr build manifest.json
```
This defaults to using a source VM to clone called 'centos7', but the
script will take the source vm as a parameter (--srcvm) if desired.

Note that if the centos7 VM is not currently defined, the script can be
told to define it first (--xml).

The build process will clone the VM's and set VM attributes according to the
manifest. It will then configure the static DHCP assignment and a host entry
for DNS for all hosts in the manifest.

Once built, the VMs can be starting via the 'start' action:
```
$ ./bin/kvm-mgr.sh start manifest.json
```

The new vm's will all have the same 'centos7' hostname as a result of the
clone process (or whatever hostname was set. The script has the 'sethostname'
action to iterate through all VM's in a manifest and set the hostname
accordingly.
