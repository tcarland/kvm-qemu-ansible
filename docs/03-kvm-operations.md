KVM Operations
===============

KVM Operation guide for managing VMs across a KVM Cluster.

<br>

---

# Table Of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Storage Pools](#storage-pools)
- [Creating A Base VM Image](#creating-a-base-vm-image)
  - [Ubuntu Installs](#ubuntu-installs)
  - [Local-Only VMs](#local-only-vms)
- [Building Virtual Machines](#building-virtual-machines)
- [Starting VMs and Setting Hostnames](#starting-vms-and-setting-hostnames)
- [Modifying Existing VMs](#modifying-existing-vms)
- [Stop vs Destroy vs Delete](#stop-vs-destroy-vs-delete)
- [Deleting Virtual Machines Manually](#deleting-virtual-machines-manually)
- [Destroying Virtual Machines by Manifest](#destroying-virtual-machines-by-manifest)
- [Validate Host Resources](#validate-host-resources)
  - [Create a Consolidated Manifest](#create-a-consolidated-manifest)
- [Migrating Virtual Machines in Offline Mode](#migrating-virtual-machines-in-offline-mode)
- [Adding Disks to a Virtual Machine, Offline](#adding-disks-to-a-virtual-machine-offline)
- [Virtual Machine Snapshots](#virtual-machine-snapshots)


## Overview

Once the Ansible playbooks have successfully installed KVM, all hosts
should be configured with a KVM Hypervisor, a network bridge, and
optionally a NFS share for secondary storage. The playbooks do not,
however, configure storage pools or networking on the nodes. The
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
```json
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

- The 'kvmsh' utility to be distributed to all nodes and placed in the system path.
  ```sh
  clush -g lab --copy kvmsh
  clush -g lab 'sudo cp kvmsh /usr/local/bin'
  clush -g lab 'rm kvmsh'
  ```
- *DnsMasq* should be installed on the management node where 'kvm-mgr.sh' is
  run from. This is used to provide DNS configuration and Static IP assignments
  for the cluster via DHCP.

- The user running the *kvm-mgr.sh* script should have sudo rights with NOPASSWD set.
  The script will automatically configure the DHCP static lease based on the
  provided manifest on build.


## Storage Pools

For a first time install, we must define our Storage Pools used to store VM and
disk images. Ideally, two storage pools are utilized, a primary storage pool and
a secondary pool. The primary storage pool is intended for local, direct-attached
storage for hosting VM images running on that given node.  The (optional) secondary
storage pool would be a NFS Share for storing source images, cloned VMs, snapshots, etc.

- Creating the primary storage pool. Note the storage pool path should be made
  consistent across all nodes.
  ```sh
  # default pool is our local, primary storage pool.
  # kvmsh will create, build, and start the pool
  clush -B -g lab 'kvmsh create-pool /data01/kvm-primary default'
  clush -B -g lab 'kvmsh pool-autostart default'
  ```

  For reference purposes, the following is the `virsh` equivalent of the above
  commands:
  ```sh
  clush -B -g lab 'virsh --connect qemu:///system pool-define-as default dir - - - - "/data01/kvm-primary"'
  clush -B -g lab 'virsh --connect qemu:///system pool-build default'
  clush -B -g lab 'virsh --connect qemu:///system pool-start default'
  clush -B -g lab 'virsh --connect qemu:///system pool-autostart default'
  ```

- If the NFS Server role was deployed and, for example, the share is available as
  '/secondary', we would add the storage-pool same as above.
  ```sh
  clush -B -g lab 'kvmsh create-pool /kvm-secondary secondary'
  ```
  The virsh equivalent to above:
  ```sh
  clush -B -g lab 'virsh --connect qemu:///system pool-define-as secondary dir - - - - "/kvm-secondary"'
  clush -B -g lab 'virsh --connect qemu:///system pool-build secondary'
  clush -B -g lab 'virsh --connect qemu:///system pool-start secondary'
  ```

- Verify the pools via pool-list:
  ```sh
  clush -B -g lab 'kvmsh pool-list'
  # virsh equivalent command
  clush -B -g lab 'virsh --connect qemu:///system pool-list --all'
  ```

- Ensure AppArmor permissions are configured for the storage location.
  On systems using AppArmor, issues can arrive with block file chains created
  from external snapshots. Add permissions to the apparmor local profile,
  */etc/apparmor.d/local/abstractions/libvirt-qemu*. The provided Ansible
  should configure these permissions.
  ```
  /data01/kvm-primary/** rwk,
  /kvm-secondary/** rwk,
  ```

## Creating a Base VM Image

The managment script, `kvm-mgr.sh`, relies on a base VM image when building
the VM's. This base images is used across all nodes to build the environment.
By default, the scripts use an Ubuntu 24.04 image as the source when creating
VMs from scratch, but other ISO's can be provided by the `--image` command
option to `kvmsh` or by setting KVMSH_DEFAULT_IMAGE in the environment.

Since the resulting base VM will be cloned by all nodes when building VM, the
VM should be created on the NFS Storage pool (secondary) to make it immediately
available to all hosts.

When creating a new VM, the `kvmsh` script looks for the source ISO in a path
relative to the storage pool in use, so we ensure the ISO is also stored in the
same storage pool.
```sh
ssh nfs01 'ls -l /kvm-secondary'
total 10430984
-rw-rw-r-- 1 libvirt-qemu kvm  1215168512 Mar 29 07:27 ubuntu-24.04.1-live-server-amd64.iso
```

The base VM can then be created on any node and pointed to the secondary pool.
```sh
kvmsh --pool secondary --console create ubuntu24.04
```

This will attach to the console of the new VM to provide access to the
installer.  Note that the networking interface should be set to start
at boot with DHCP. Once complete, the VM will exist in our secondary pool:
```
[idps@sm-01]$ ls -l /secondary
total 8175440
-rw-rw-r-- 1 tca tca  1215168512 Mar 29 07:27 ubuntu-24.04.1-live-server-amd64.iso
-rw-r--r-- 1 tca tca 26843545600 Mar 28 06:26 ubuntu24.04-vda.img
```

Another example using a larger boot disk (default is 40G)
```sh
KVMSH_DEFAULT_IMAGE="CentOS-7-x86_64-Minimal-2003.iso"
kvmsh --pool secondary --bootsize 80 --console --os centos7 create centos7-80
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

The final step would be to stop the VM and acquire the
XML Definition for use across all remaining nodes to define our source VM.
```sh
kvmsh stop ubuntu24.04
kvmsh dumpxml ubuntu24.04 > ubuntu2404.xml

# copy xml to all hosts
clush -g lab --copy ubuntu2404.xml

# Now we define our base VM across all nodes
clush -g lab 'kvmsh define ubuntu2404.xml'
```

### Ubuntu Installs

Ubuntu installs using the console often require configuring *grub*
correctly for console access post-install.  Once the installer completes,
add `console=ttyS0` to */etc/default/grub* and run `update-grub`
accordingly. Ensure to enable the openSSH server during the install
process to ensure access to the vm.

Ubuntu has a number of install options with varying degrees of
difficulty for installing with KVM and `virt-install`.

- A Web-based install uses a *http* location as the `image` which means
  all assets are downloaded. For Ubuntu 20.04, for example, the web
  installer URL provided to `--image` would be set to
  `http://us.archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/`.
  This method is convienient but is likely to be deprecated in the near future.

- Ubuntu live ISO images place the ISO boot kernel (vmlinuz) in a
  subdirectory (typically named `casper`) which causes `virt-install`
  to not be able to boot the ISO. Ubuntu still provides a legacy
  ISO image installer, however this also is intended to be deprecated.
  This is still the best *local* install method for Ubuntu 22.04. The
  link for these legacy install ISO's was listed in the *focal* release
  notes as being [here](http://cdimage.ubuntu.com/ubuntu-legacy-server/releases/20.04/release/).

- Working with the standard live iso images may require extracting the
  image to the local filesystem to allow passing the kernel boot options
  to `virt-install` which would look like the following:
  ```
  --boot kernel=casper/vmlinuz,initrd=casper/initrd,kernel_args="console=ttyS0"
  ```
  Note, that mounting the ISO as Read-only won't work as the installer
  wants the *initrd* image to be writeable.

- On successful install of the OS, the *linux-kvm-tools* package should
  be installed. Also note that *openssh-server* is typically not installed
  by default.


### Local-only VMs

While this document covers running KVM nodes in a distributed fashion,
VMs can be created as local-only instances by using KVM's default NAT
interface *virbr0* or `--network "bridge=virbr0"` provided to *kvmsh*.


## Building Virtual Machines

Building the environment is accomplished by providing the JSON manifest
to the `kvm-mgr.sh` script.
```sh
./bin/kvm-mgr.sh build manifest.json
```
This defaults to using a source VM to clone called 'ubuntu20.04', but the
script will take the source vm as a parameter (--srcvm) if desired.

Note that if the Ubuntu VM is not currently defined, the script can be
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
```sh
./bin/kvm-mgr.sh start manifest.json
```

NOTE: The new VM's will all have the same 'ubuntu2004' hostname as a result
of the clone process (or whatever hostname was used on the base image). The
script provides the 'sethostname' action to iterate through all VM's in a
manifest and set the hostname(s) accordingly.
```sh
./bin/kvm-mgr.sh sethostnames manifest.json
```

## Modifying Existing VMs

Some changes can be done on live VM's, accomplished individually
using the `kvmsh` utility. Namely, increasing the memory for a given VM,
which can be done on a live host up to the `MaxMemoryGB` limit defined for
the VM. Most other changes to the VM generally require stopping the VM first
to edit the VM. whether by *virsh* or by XML. The XML should not be edited by
hand, but if absolutely necessary, the VM should be undefined first.
```sh
kvmsh dumpxml tdh-m01 > tdh-m01.xml
vmsh undefine tdh-m01
#  [ edit the XML ]
kvmsh define tdh-m01.xml
```

Often, simply rebuilding the VM's is the fastest route. To do so, we would
define a focused manifest for just the VMs to be affected. Destroy the
current VMs, update the manifest as desired, and rebuild the VMS.
```sh
cp all.json zookeepers.json
vi zookeepers.json         # reduce manifest to only the hosts in question
./bin/kvm-mgr.sh delete zookeepers.json
vi zookeepers.json         # update values as desired
./bin/kvm-mgr.sh -x centos7.xml build
```

Note that any adjustments to live instances that wish to be persisted should
also be updated in the corresponding manifest.

Resizing disks requires the VM to be stopped. Use the *qemu-img* tool to
resize the disk and then follow normal filesystem methods to grow or shrink
the filesystem. Alternatively, the *virt-resize* command can lvexpand and
grow the filesystem in one command.
```sh
qemu-img resize -f raw <path/to/disk.img> [(+|-)size(k, M, G or T)]
```

## Stop vs Destroy vs Delete

Terminology in KVM land, namely virsh from libvirt, defines the term `destroy`
for terminating VMs and is synonymous to `stop`. These actions also work
via the manifest for stopping a group of VMs across the cluster. Individual VMs
can be stopped directly using the local 'kvmsh' script.
```sh
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
```sh
ssh t05 'kvmsh delete tdh-d03'
Domain tdh-d03 has been undefined

ssh t05 'kvmsh vol-list'
 tdh-d01-vda.img /data01/primary/tdh-d01-vda.img
 tdh-d01-vdb.img /data01/primary/tdh-d01-vdb.img
 tdh-d03-vda.img /data01/primary/tdh-d03-vda.img
 tdh-d03-vdb.img /data01/primary/tdh-d03-vdb.img

ssh sm-05 'kvmsh vol-delete tdh-d03-vda.img'
ssh sm-05 'kvmsh vol-delete tdh-d03-vdb.img'
```

Or in a more convenient fashion:
```bash
vmname="tdh-d03"
for x in $( kvmsh vol-list | grep $vmname | \
    awk '{ print $1 }' ); do kvmsh vol-delete $x; done
```


## Deleting Virtual Machines by Manifest

- Create a JSON manifest containing the VMs in question.
  Verify the manifest is accurate since we are permanently deleting.
  ```json
  $ cat tdh-datanodes.json
  [
      {
          "host" : "t04.tdh.internal",
          "vmspecs" : [
              {
                  "name" : "tdh-d03",
                  "description" : "TDH Datanode",
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
  ~/bin/kvm-mgr.sh delete tdh-datanodes.json
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
  ./bin/kvm-mgr.sh dumpxml tdh-datanodes.json
  ./bin/kvm-mgr.sh --keep-disks delete tdh-datanodes.json
  ```


## Validate Host Resources

The `vm-consumption.sh` script will provide the resource consumptions per node.
The input parameter is a JSON manifest file.
```sh
./bin/vm-consumptions.sh <manifest.json>
```


### Create a Consolidated Manifest

The `mergeAllManifests.sh` script is used to consolidate all JSON manifests,
under `~/manifests` by default, into one for use with `vm-consumptions.sh`.
```sh
~/bin/mergeAllManifests.sh
cp manifest.json ~/kvm-manifest.json
./bin/vm-consumptions.sh ~/kvm-manifest.json

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
Just to be clear, offline migration implies the VM should always be
stopped first.

This project configures and relies on the primary storage being the
same path on all nodes, which makes moving VM's easier as little to
no change to the VM Specification is needed.

Steps to Migrate:

1. Save the VM Specification.
    ```sh
    kvmsh dumpxml vmname > vmname.xml
    ```

2. Copy vm disks to the primary storage on the alternate host.

3. Copy the xml the new host and define the vm.
    ```sh
    kvmsh define vmname.xml
    ```

4. Remove the VM specification from the original host.
    ```sh
    kvmsh delete vmname.xml
    ```

5. Remove volumes from original host
    ```sh
    kvmsh vol-delete vmname-vda.img
    ```

6. Start the VM on the new host
    ```sh
    kvmsh start vmname
    ```

Lastly, update the kvm-mgr manifest accordingly.


## Adding disks to a Virtual Machine Offline

- Stop the VM first
  ```sh
  kvmsh stop <name>
  ```

- Create and attach the new disks
  ```sh
  kvmsh -D 2 -d 40G attach-disk <name>
  ```

## Converting disk formats

Convert a raw image to qcow2.
```sh
qemu-img convert -f raw -O qcow2 image.img image.qcow2
```

Convert a vmware vmdk to qcow2
```sh
qemu-img convert -f vmdk -O qcow2 image.vmdk image.qcow2
```

## Virtual Machine Snapshots

Internal snapshots within KVM-Qemu require disk images in the *qcow2*
format. This style of snapshot is contained within the qcow format and
is generally considered poorly maintained upstream by QEMU.

Instead, *kvmsh* uses external snapshots, which support either *raw* or
*qcow2* images. The current implementation supports snapshotting the
image state only, while the host is offline. Machine memory state, while
running, is currently not supported.

Snapshot operations are straight-forward commands that take the vm name
and the snapshot name where appropriate. The primary commands are
*snapshot-create*, *snapshot-delete*, *snapshot-revert* and *snapshot-info*.

Note that *snapshot-revert* is not currently supported with external
snapshots in kvm-qemu and must be reverted manually via *edit*.
Note that external snapshots will work with *raw* disk images, but will
change the file-type to *qcow2* when pointing to a snapshot. If
manually reverting to the base img, ensure the type is also changed
back to *raw* to match.

### Merging snapshots

Showing the current backing chain of a snapshot.
```sh
qemu-img info --force-share --backing-chain cur.qcow2
kvmsh domblklist <vm>
```

**Method 1** - Online virsh *blockcommit*
```sh
kvmsh blockcommit <vm> vda --base=vm-vda.img --top=vm-vda.snap-name --wait --verbose
```

The alternate virsh command of *blockpull* pulls a snapshot layer
forward into the active layer.

**Method 2** - Offline merge via *qemu-img*

Given an image chain of 'base <- sn1 <- sn2 <- sn3' and reducing the chain by
merging *sn2* into *sn1*
```sh
qemu-img commit sn2.qcow2
qemu-img rebase -u -b sn1.qcow2 sn3.qcow2
```
