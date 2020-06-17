kvm-qemu-ansible
=================

 Ansible playbook for installing KVM-QEMU on either RHEL/Centos or Ubuntu
Linux systems. This is intended for deploying KVM across a cluster of nodes.
The Ansible roles do not configure any primary storage pools, but there are NFS
roles for utilizing NFS as a secondary storage pool. More about configuring the
storage pools comes later in the document.

  This also assumes the networking layer for the bridge network to be used by
Virtual Machines is also configured as all VMs are intended to run with a bridged
network across nodes. More information about configuring the host bridge network
is provided below.

## Ansible Configuration

Inventory vault file format contains ssh keys for users and service accounts:
```
kvm_ssh_ids:
  tca:
    ssh_id: ''
  tdh:
    ssh_id: ''
```

Inventory vars, of note `kvm_users` must be in the kvm and libvirt groups.:
```
---
kvm_users:
 - tca
 - tdh

kvm_groups:
 - libvirt
 - kvm

nfs_domain: 'tdh.internal'
nfs_storage_server: 'tdh01.tdh.internal'
nfs_storage_export: '/data01/secondary'
nfs_storage_mountpoint: '/secondary'

kvm_primary_storage: '/data01/primary'

sysctl:
  net:
    bridge:
      bridge_arptables: "0"
      bridge_ip6tables: "0"
      bridge_iptables: "0"
    ipv4:
      ip_forward: "1"
      conf:
        accept_source_route: "0"
        rp_filter: "0"
    ipv6:
      conf:
        disable_ipv6: "0"
  vm:
    swappiness: "1"


dnsmasq_primary_resolver: '8.8.8.8'
dnsmasq_secondary_resolver: '8.8.4.4'

dnsmasq_kvm_domain: 'tdh.internal'

dhcp_range_start: '10.10.5.130'
dhcp_range_end: '10.10.5.250'
dhcp_range_netmask: '255.255.255.0'
dhcp_router_ip: '10.10.5.1'
```



## KVM Setup

  Once Ansible has been run, all hosts should be configured with a KVM
Hypervisor, a network bridge, and optionally a NFS share for secondary
storage. The ansible does not, however, configure any storage pools or
networking on the nodes.  The following sections discuss configuring KVM
for use across a cluster by configuring Bridged Networking for the nodes
and Storage pools.

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


## Requirements

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


## DnsMasq

The user running the kvm-mgr.sh script should have sudo rights with NOPASSWD set.
The script will automatically configure the DHCP static lease based on the
provided manifest. The ansible already installs and configures DnsMasq as a
part of the `mgmt-server` role.


## Storage Pools

  For a first time install, we must define our Storage Pools used to store
VM and disk images. We use two storage pools, a primary and a secondary. The
primary storage pool is intended for local, direct-attached storage for VMs
running on that given node. The optional secondary storage would be a NFS Share
for storing our source images, cloned VMs, or snapshots, etc.

Create the primary storage pool:
```
# default pool is our local, primary storage pool.
#  kvmsh will create, build, and start the pool
clush -B -g lab 'kvmsh create-pool /data01/primary default'
clush -B -g lab 'kvmsh pool-autostart default'

# the virsh equivalent:
#clush -B -g lab 'virsh --connect qemu:///system pool-define-as default dir - - - - "/data01/primary"'
#clush -B -g lab 'virsh --connect qemu:///system pool-build default'
#clush -B -g lab 'virsh --connect qemu:///system pool-start default'
#clush -B -g lab 'virsh --connect qemu:///system pool-autostart default'
```

If the NFS Server role was deployed and, for example, the share is available as
'/secondary', we would add the storage-pool same as above.
```
clush -B -g lab 'kvmsh create-pool /secondary secondary'


# the virsh equivalent
#clush -B -g lab 'virsh --connect qemu:///system pool-define-as secondary dir - - - - "/secondary"'
#clush -B -g lab 'virsh --connect qemu:///system pool-build secondary'
#clush -B -g lab 'virsh --connect qemu:///system pool-start secondary'
```

Verify the pools via pool-list:
```
clush -B -g lab 'kvmsh pool-list'

# virsh equivalent command
clush -B -g lab 'virsh --connect qemu:///system pool-list --all'
```


## Networking

  The *kvm-qemu* role does **not** configure the networking component of
setting up the host bridge `br0`. This should be done ahead of time, carefully
or with proper console access.

Disable the use of NetworkManager on our cluster nodes:
```
clush -a 'sudo systemctl stop NetworkManager'
clush -a 'sudo systemctl disable NetworkManager'
```

Configure *ifcfg-br0* in `/etc/sysconfig/network-scripts/` :
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


## Creating a Base VM Image

The build script, `kvm-mgr.sh`, relies on a base VM image to use when building
the VM's. This base images is used across all nodes to build the environment. By
default, the scripts use a Centos7 ISO as source iso when creating VMs from
scratch, but other ISO's can be provided by the `--image` command option.

Since the resulting base VM will be cloned by all nodes when building VM, the
VM should be created on the Secondary Storage pool (NFS) to make it available
to all hosts.

When creating a new VM, the `kvmsh` script looks for the source ISO in a path
relative to storage pool in use, so we ensure the ISO is also stored in the
Secondary pool.
```
$ ssh sm-01 'ls -l /secondary'
total 2525812
-rw-r--r--. 1 root idps   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-1908.iso
```

The base VM can then be created on any node and pointed to the secondary pool.
```
$ kvmsh --pool secondary --console create centos7
```

This will attach to the console of the new VM to provide access to the
ISO installer.  Note that the networking interface should be set to start
at boot with DHCP. Once complete, the VM will exist in our secondary pool:
```
$ ls -l /secondary
-rw-r--r--. 1 root root 42949672960 Apr 27 13:12 centos7-vda.img
-rw-r--r--. 1 root root   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-1908.iso
```

Another example using a larger boot disk (default is 40G)
```
$ kvmsh --pool secondary --bootsize 80 --console create centos7-80
```

Once installed, we can add some additional requirements that are needed
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

 # copy centos7.xml to all hosts
 [admin-01]$ scp sm-01:centos7.xml .
 [admin-01]$ clush -g lab --copy centos7.xml

 # Now we define our base VM across all nodes
 [admin-01]$ clush -g lab 'kvmsh define centos7.xml'
```


## Building VMs

 Building the environment is accomplished by providing the JSON manifest to the
`kvm-mgr.sh` script.
```
$ ./bin/kvm-mgr.sh build manifest.json
```
This defaults to using a source VM to clone called 'centos7', but the
script will take the source vm as a parameter (--srcvm) if desired.

Note that if the centos7 VM is not currently defined, the script can be
told to define it first (--xml).

The build process will clone the VM's and set VM attributes according to the
manifest. It will then configure the static DHCP assignment and a host entry
for DNS for all hosts in the manifest.

The **kvm-mgr** script should *always* be run from the admin host that is
running DnsMasq, which is used to statically assign IP's to the VMs.
`kvm-mgr.sh` will update dnsmasq accordingly with the lease info needed
for statically assigning IP's to the new VMs as well as /etc/hosts.


## Starting VMs - Setting Hostnames

Once built, the VMs can be started by via the 'start' action:
```
 $ ./bin/kvm-mgr.sh start manifest.json
```

NOTE: The new VM's will all have the same 'centos7' hostname as a result of the
clone process (or whatever hostname was set on the base image). The script
provides the 'sethostname' action to iterate through all VM's in a manifest
and set the hostname accordingly.
```
 $ ./bin/kvm-mgr.sh sethostname manifest.json
```


## Modifying existing VMs

Some changes can be done on live VM's, accomplished individually
using the `kvmsh` utility. Namely, increasing the memory for a given VM,
which can be done on a live host up to the `MaxMemoryGB` limit defined for
the VM. Most other changes to the VM generally require stopping the VM first
to edit the VM. whether by *virsh* or by XML. The XML should not be edited by
hand, but if absolutely necessary, the VM should be undefined first.
```
 $ kvmsh dumpxml itc-generator01 > itc-generator01.xml
 $ vmsh undefine itc-generator01
 #  [ edit the XML ]
 $ kvmsh define itc-generator01.xml
```

Often, simply rebuilding the VM's is the fastest route. To do so, we would
define a focused manifest for just the VMs to be affected. Destroy the
current VMs, update the manifest as desired, and rebuild the VMS.
```
 $ cp all.json zookeepers.json
 $ vi zookeepers.json         # reduce manifest to only the hosts in question
 $ ./bin/kvm-mgr.sh delete zookeepers.json
 $ vi zookeepers.json         # update values as desired
 $ ./bin/kvm-mgr.sh -x centos7.xml build
```

Note that any adjustments to live instances that wish to be persisted should
also be updated in the corresponding manifest.


## Stop vs. Destroy vs. Delete

Terminology in KVM land, namely virsh from libvirt, defines the term `destroy`
for terminating VMs and is synonymous `stop`. These actions also work
by manifest for stopping a group of VMs across the cluster. Individual VMs
can be stopped directly using the local 'kvmsh' script.
```
ssh sm-04 'kvmsh stop itc-statedb02'
```

Running 'delete' is a destructive process as the VM is stopped and completely
undefined. libvirt actions however will not remove associated volumes and
this is true for our 'kvmsh' wrapper as well. Running `delete` from
*kvm-mgr.sh* using a manifest, however, will automatically remove all volumes
unless the `--keep-disks` option is provided.


### Manually deleting a VM via kvmsh:

 If the environment is wiped or vms deleted manually, the volumes
might persist in the storage pool without having the VM defined.

```
 $ ssh sm-05 'kvmsh delete itc-statedb03'
 Domain itc-itc-statedb03 has been undefined

 $ ssh sm-05 'kvmsh vol-list'
 itc-statedb01-vda.img /data01/primary/itc-statedb01-vda.img
 itc-statedb01-vdb.img /data01/primary/itc-statedb01-vdb.img
 itc-statedb03-vda.img /data01/primary/itc-statedb03-vda.img
 itc-statedb03-vdb.img /data01/primary/itc-statedb03-vdb.img

 $ ssh sm-05 'kvmsh vol-delete itc-statedb03-vda.img'
 $ ssh sm-05 'kvmsh vol-delete itc-statedb03-vdb.img'
```

Or in a more convenient fashion:
```
for x in $( kvmsh vol-list | grep $vmname | \
    awk '{ print $1 }' ); do kvmsh vol-delete $x; done
```

### Destroying VMs from Manifest

Create a JSON manifest containing the VMs in question.
Verify the manifest is accurate since we are permanently deleting.
```
$ cat statedb.json
[
    {
        "host" : "sm-04.itc.internal",
        "vmspecs" : [
            {
                "name" : "itc-statedb03",
                "description" : "StateDb (Redis) for PhyConv"
                "hostname" : "itc-statedb03.itc.internal",
                "ipaddress" : "172.30.10.193",
                "vcpus" : 2,
                "memoryGb" : 8,
                "maxMemoryGb" : 12,
                "numDisks" : 1,
                "diskSize" : 60
            }
        ]
    }
]
```

 Now delete the VMs, noting all disks are also removed.
```
$ ~/bin/kvm-mgr.sh delete statedb.json
WARNING! 'delete' action will remove all VM's!
    (Consider testing with --dryrun option)
Are you certain you wish to continue?  [y/N] y
( ssh sm-01 'kvmsh delete itc-statedb03' )
Domain itc-itc-statedb03 has been undefined
( ssh sm-01 'kvmsh vol-delete "/data01/primary/itc-statedb03-vda.img"' )
Vol /data01/primary/itc-statedb03-vda.img deleted.
( ssh sm-01 'kvmsh vol-delete "/data01/primary/itc-statedb03-vdb.img"' )
Vol /data01/primary/itc-statedb03-vdb.img deleted.
kvmsh Finished.
```

### Delete a VM without destroying assets.  
A given VM under management of libvirt internally stores the XML definition
of the VM which also defines the attached volumes. The individual VM
definitions can be exported via `kvmsh dumpxml <name> > name.xml` to save
the definition, as well as using the manifest to perform the action across
multiple nodes. Note the *kvm-mgr.sh* switch `--keep-disks` to
save the volumes.
```
$ ./bin/kvm-mgr.sh dumpxml manifest.com
$ ./bin/kvm-mgr.sh --keep-disks delete statedb.json
```

### Validate Host Resources

The `vm-consumption.sh` script will provide the resource consumptions per node.
The input parameter is a JSON manifest file.
```
$ ./bin/vm-consumptions.sh ~/kvm-manifest.json

sm-01 :
  cpus total:  96  memory total:  512
  cpus used:   12   memory used:  96
 ------------------------------------------------
  cpus avail:  84  memory avail:  416

sm-02 :
  cpus total:  96  memory total:  512
  cpus used:   12   memory used:  96
 ------------------------------------------------
  cpus avail:  84  memory avail:  416

sm-03 :
  cpus total:  96  memory total:  512
  cpus used:   30   memory used:  90
 ------------------------------------------------
  cpus avail:  66  memory avail:  422

sm-04 :
  cpus total:  96  memory total:  512
  cpus used:   40   memory used:  122
 ------------------------------------------------
  cpus avail:  56  memory avail:  390

sm-05 :
  cpus total:  96  memory total:  512
  cpus used:   32   memory used:  100
 ------------------------------------------------
  cpus avail:  64  memory avail:  412
 ```
