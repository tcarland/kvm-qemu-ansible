KVM Operations
===============

KVM Operation guide for managing VMs across a KVM Cluster.

<br>

--- 

# Table Of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Storage Pools](#storage-pools)
- [Creating A Base VM](#creating-a-base-vm-image)
- [Building VirtualMachines](#building-vms)
- [Starting VMs and Setting Hostnames](#starting-vms-and-setting-hostnames)
- [Modifying Existing VMs](#modifying-existing-vms)
- [Stop vs Destroy vs Delete](#stop-vs-destroy-vs-delete)
- [Deleting Virtual Machines Manually](#deleting-virtual-machines-manually)
- [Destroying Virtual Machines by Manifest](#destroying-virtual-machines-by-manifest)
- [Validate Host Resources](#validate-host-resources)
  -[Create a Consolidated Manifest](#create-a-consolidated-manifest)
- [Migrating Virtual Machines in Offline Mode](#migrating-virtual-machines-in-offline-mode)


## Overview

  Once the Ansible playbooks have successfully installed KVM, all 
hosts should be configured with a KVM Hypervisor, a network bridge, 
and optionally a NFS share for secondary storage. The playbooks do 
not, however, configure storage pools or networking on the nodes. The 
networking should already be configured before continuing with these 
steps to configure the storage pools.

  Additionally, there are two management scripts provided for managing
Virtual Machines across the infrastructure.

- **kvmsh**:  This tool primarily wraps the usage of libvirt related 
tools such as 'virsh', 'virt-install', and 'virt-clone'. It utilizes 
the same command structure as 'virsh', but provides the ability to 
perform the additional install and cloning steps along with defaults 
for use in a clustered setup. This tool is run on individual nodes to 
manipulate the VMs on that given node.

- **kvm-mgr.sh**:  A script for managing VMs across a cluster from a
single management node. Relying on SSH host keys, the tool takes a 
manifest describing the VM configurations and utilizes *kvmsh* per node 
to implement various actions like create, start, stop, and delete.

The inventory for KVM hosts is a JSON Manifest of the following schema:
```
[
    {
        "host" : "t01",
        "vmspecs" : [
          {
              "name" : "tdh-m01",
              "hostname" : "tdh-m01.tdh.internal",
              "ipaddress" : "173.30.5.11",
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

- A management node (like an Ansible server) for running *kvm-mgr.sh* using 
  SSH Host Keys.

- `clustershell` for running 'kvmsh' across nodes is not directly required
   but is very useful and recommended.

- The 'kvmsh' utility to be distributed to all nodes and placed in the
  system path.
  ```
  clush -g lab --copy kvmsh
  clush -g lab 'sudo cp kvmsh /usr/local/bin'
  clush -g lab 'rm kvmsh'
  ```
- *DnsMasq* should be installed on the management node where 'kvm-mgr.sh' is
  run from. This is used to provide DNS configuration and Static IP assignments 
  for the cluster via DHCP.

- The user running the kvm-mgr.sh script should have sudo rights with NOPASSWD set.
  The script will automatically configure the DHCP static lease based on the
  provided manifest on build.

## Storage Pools

  For a first time install, we must define our Storage Pools used to store
VM and disk images. Ideally, two storage pools are utilized, a primary storage
pool and a secondary pool. The primary storage pool is intended for local, 
direct-attached storage for hosting VM images running on that given node. 
The (optional) secondary storage would be a NFS Share for storing source images, 
cloned VMs, or snapshots, etc.

- Creating the primary storage pool. Note the storage pool path should be made 
consistent across all nodes.
  ```
  # default pool is our local, primary storage pool.
  # kvmsh will create, build, and start the pool
  clush -B -g lab 'kvmsh create-pool /data01/primary default'
  clush -B -g lab 'kvmsh pool-autostart default'
  ```
  For reference purposes, the following is the `virsh` equivalent of the above
  commands:
  ```
  clush -B -g lab 'virsh --connect qemu:///system pool-define-as default dir - - - - "/data01/primary"'
  clush -B -g lab 'virsh --connect qemu:///system pool-build default'
  clush -B -g lab 'virsh --connect qemu:///system pool-start default'
  clush -B -g lab 'virsh --connect qemu:///system pool-autostart default'
  ```

- If the NFS Server role was deployed and, for example, the share is available as
'/secondary', we would add the storage-pool same as above.
  ```
  clush -B -g lab 'kvmsh create-pool /secondary secondary'
  ```
  The virsh equivalent to above:
  ```
  clush -B -g lab 'virsh --connect qemu:///system pool-define-as secondary dir - - - - "/secondary"'
  clush -B -g lab 'virsh --connect qemu:///system pool-build secondary'
  clush -B -g lab 'virsh --connect qemu:///system pool-start secondary'
  ```

- Verify the pools via pool-list:
  ```
  clush -B -g lab 'kvmsh pool-list'
  # virsh equivalent command
  clush -B -g lab 'virsh --connect qemu:///system pool-list --all'
  ```

## Creating a Base VM Image

  The managment script, `kvm-mgr.sh`, relies on a base VM image when building
the VM's. This base images is used across all nodes to build the environment. By
default, the scripts use a Centos7 ISO as source iso when creating VMs from
scratch, but other ISO's can be provided by the `--image` command option to `kvmsh`
or by setting KVMSH_DEFAULT_IMAGE in the environment.

  Since the resulting base VM will be cloned by all nodes when building VM, the
VM should be created on the Secondary Storage pool (NFS) to make it immediately 
available to all hosts.

  When creating a new VM, the `kvmsh` script looks for the source ISO in a path
relative to the storage pool in use, so we ensure the ISO is also stored in the
same storage pool.
```
$ ssh sm-01 'ls -l /secondary'
total 2525812
-rw-r--r--. 1 root idps   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-2003.iso
```

The base VM can then be created on any node and pointed to the secondary pool.
```
$ kvmsh --pool secondary --console create centos7
```

This will attach to the console of the new VM to provide access to the
ISO installer.  Note that the networking interface should be set to start
at boot with DHCP. Once complete, the VM will exist in our secondary pool:
```
[idps@sm-01]$ ls -l /secondary
-rw-r--r--. 1 root root 42949672960 Apr 27 13:12 centos7-vda.img
-rw-r--r--. 1 root idps   987758592 Apr 21 15:34 CentOS-7-x86_64-Minimal-2003.iso
```

Another example using a larger boot disk (default is 40G)
```
KVMSH_DEFAULT_IMAGE="CentOS-7-x86_64-Minimal-2003.iso"
$ kvmsh --pool secondary --bootsize 80 --console create centos7-80
```

Once installed, we can add some additional requirements that are needed
across our environment. Most importantly, creating any role or user account(s)
with the correct SSH key(s) and configuring the resolvers to point to our
internal DNS Server, which is the Management Node. This list provides
this and some other items worth configuring into the base image:

- Set the resolvers to the DnsMasq server.
- Configure ssh keys for accounts as needed.
- Set NOPASSWD (visudo) for the wheel or sudo group
- Disable firewalld if desired.
- Disable selinux if desired.
- Disable NetworkManager if desired.

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

  Building the environment is accomplished by providing the JSON manifest 
to the `kvm-mgr.sh` script.
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
running *DnsMasq*, which is used to statically assign IP's to the VMs.
`kvm-mgr.sh` will update dnsmasq accordingly with the lease info needed
for statically assigning IP's to the new VMs as well as /etc/hosts.

## Starting VMs and Setting Hostnames

Once built, the VMs can be started by via the 'start' action:
```
 $ ./bin/kvm-mgr.sh start manifest.json
```

NOTE: The new VM's will all have the same 'centos7' hostname as a result of the
clone process (or whatever hostname was set on the base image). The script
provides the 'sethostname' action to iterate through all VM's in a manifest
and set the hostname accordingly.
```
 $ ./bin/kvm-mgr.sh sethostnames manifest.json
```

## Modifying Existing VMs

Some changes can be done on live VM's, accomplished individually
using the `kvmsh` utility. Namely, increasing the memory for a given VM,
which can be done on a live host up to the `MaxMemoryGB` limit defined for
the VM. Most other changes to the VM generally require stopping the VM first
to edit the VM. whether by *virsh* or by XML. The XML should not be edited by
hand, but if absolutely necessary, the VM should be undefined first.
```
 $ kvmsh dumpxml tdh-m01 > tdh-m01.xml
 $ vmsh undefine tdh-m01
 #  [ edit the XML ]
 $ kvmsh define tdh-m01.xml
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


## Stop vs Destroy vs Delete

Terminology in KVM land, namely virsh from libvirt, defines the term `destroy`
for terminating VMs and is synonymous to `stop`. These actions also work
via the manifest for stopping a group of VMs across the cluster. Individual VMs
can be stopped directly using the local 'kvmsh' script.
```
ssh sm-04 'kvmsh stop tdh-m01'
```

Running 'delete' is a destructive process as the VM is stopped and completely
undefined. libvirt actions however will not remove associated volumes and
this is true for our 'kvmsh' wrapper as well. Running `delete` from
*kvm-mgr.sh* using a manifest, however, will automatically remove all volumes
unless the `--keep-disks` option is provided.

## Deleting Virtual Machines manually

 If the environment is wiped or vms deleted manually, the volumes
might persist in the storage pool without having the VM defined.

```
 $ ssh t05 'kvmsh delete tdh-d03'
 Domain tdh-d03 has been undefined

 $ ssh t05 'kvmsh vol-list'
 tdh-d01-vda.img /data01/primary/tdh-d01-vda.img
 tdh-d01-vdb.img /data01/primary/tdh-d01-vdb.img
 tdh-d03-vda.img /data01/primary/tdh-d03-vda.img
 tdh-d03-vdb.img /data01/primary/tdh-d03-vdb.img

 $ ssh sm-05 'kvmsh vol-delete tdh-d03-vda.img'
 $ ssh sm-05 'kvmsh vol-delete tdh-d03-vdb.img'
```

Or in a more convenient fashion:
```
vmname="tdh-d03"
for x in $( kvmsh vol-list | grep $vmname | \
    awk '{ print $1 }' ); do kvmsh vol-delete $x; done
```

## Deleting Virtual Machines by Manifest

- Create a JSON manifest containing the VMs in question.
  Verify the manifest is accurate since we are permanently deleting.
  ```
  $ cat tdh-datanodes.json
  [
      {
          "host" : "t04.tdh.internal",
          "vmspecs" : [
              {
                  "name" : "tdh-d03",
                  "description" : "TDH Datanode"
                  "hostname" : "tdh-d03.tdh.internal",
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

- Now delete the VMs, noting all disks are also removed.
  ```
  $ ~/bin/kvm-mgr.sh delete tdh-datanodes.json
  WARNING! 'delete' action will remove all VM's!
      (Consider testing with --dryrun option)
  Are you certain you wish to continue?  [y/N] y
  ( ssh t04 'kvmsh delete tdh-d03' )
  Domain tdh-d03 has been undefined
  ( ssh t04 'kvmsh vol-delete "/data01/primary/tdh-d03-vda.img"' )
  Vol /data01/primary/tdh-d03-vda.img deleted.
  ( ssh t04 'kvmsh vol-delete "/data01/primary/tdh-d03-vdb.img"' )
  Vol /data01/primary/tdh-d03-vdb.img deleted.
  kvmsh Finished.
  ```

- Delete a VM without destroying assets.  
  A given VM under management of libvirt internally stores the XML definition
  of the VM which also defines the attached volumes. The individual VM
  definitions can be exported via `kvmsh dumpxml <name> > name.xml` to save
  the definition, as well as using the manifest to perform the action across
  multiple nodes. Note the *kvm-mgr.sh* switch `--keep-disks` to
  save the volumes.
  ```
  $ ./bin/kvm-mgr.sh dumpxml tdh-datanodes.json
  $ ./bin/kvm-mgr.sh --keep-disks delete tdh-datanodes.json
  ```

## Validate Host Resources

The `vm-consumption.sh` script will provide the resource consumptions per node.
The input parameter is a JSON manifest file.
```
$ ./bin/vm-consumptions.sh <manifest.json>
```

### Create a Consolidated Manifest

The `mergeAllManifests.sh` script is used to consolidate all JSON manifests,
under `~/manifests` by default, into one for use with `vm-consumptions.sh`.
```
$ ~/bin/mergeAllManifests.sh
$ cp manifest.json ~/kvm-manifest.json

$ ./bin/vm-consumptions.sh ~/kvm-manifest.json

t01 :
  cpus total:  96  memory total:  512
  cpus used:   12   memory used:  96
 ------------------------------------------------
  cpus avail:  84  memory avail:  416

t02 :
  cpus total:  96  memory total:  512
  cpus used:   12   memory used:  96
 ------------------------------------------------
  cpus avail:  84  memory avail:  416

t03 :
  cpus total:  96  memory total:  512
  cpus used:   30   memory used:  90
 ------------------------------------------------
  cpus avail:  66  memory avail:  422

t04 :
  cpus total:  96  memory total:  512
  cpus used:   40   memory used:  122
 ------------------------------------------------
  cpus avail:  56  memory avail:  390

t05 :
  cpus total:  96  memory total:  512
  cpus used:   32   memory used:  100
 ------------------------------------------------
  cpus avail:  64  memory avail:  412
 ```


## Migrating Virtual Machines in Offline Mode

Live VM Migration is possible with libvirt and KVM, but not covered by
this document. The following describes how to migrate VM's offline.  

- Of course, offline migration implies the VM should be stopped first.
- This project configures and relies on primary storage being the same path
  on all nodes, which makes moving VM's easier as little to no change to the
  VM Specification is needed.

Steps to Migrate.

1. Save the VM Specification.
    ```
    kvmsh dumpxml vmname > vmname.xml
    ```

2. Copy vm disks to primary storage on alternate host.

3. Copy the xml and define the new vm.
    ```
    kvmsh define vmname.xml
    ```

4. Remove the VM specification from the original host
    ```
    kvmsh delete vmname.xml
    ```

5. Remove volumes from original host
    ```
    kvmsh vol-delete volname.img
    ```

6. Start the VM on the new host
    ```
    kvmsh start vmname
    ```

Lastly, update the VM Manifest accordingly.
