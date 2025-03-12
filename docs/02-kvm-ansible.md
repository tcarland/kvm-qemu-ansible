KVM Ansible Deployment Guide
============================

Ansible is used to bootstrap systems as well as install the KVM stack 
and NFS Server/Clients.

Prior to running the Ansible Playbooks, the base storage systems to be 
used for the primary storage pool (and optional NFS Server) should already 
be created and mounted. Additionally a network bridge for *br0* should be 
configured as described in the [01-prerequisites.md](docs/01-prerequisites.md) 
document.


## Configure Inventory

The following inventory settings from *inventory/$env/group_vars/all/vars*
should be customized to provide the domain settings, storage locations, and 
IP Address ranges. The following inventory example uses a common role-account 
called *tdh* for managing KVM and is added to the three primary groups needed.

**inventory/$env/group_vars/all/vars**
```yaml
---
kvm_users:
 - tca
 - tdh

kvm_groups:
 - libvirt
 - libvirt-qemu
 - kvm

nfs_domain: 'tdh.internal'
nfs_storage_server: 'tdh01.tdh.internal'
nfs_storage_export: '/data01/secondary'
nfs_storage_mountpoint: '/secondary'

kvm_primary_storage: '/data01/primary'

dnsmasq_primary_resolver: '8.8.8.8'
dnsmasq_secondary_resolver: '8.8.4.4'

dnsmasq_kvm_domain: 'tdh.internal'

dhcp_range_start: '10.10.5.130'
dhcp_range_end: '10.10.5.250'
dhcp_range_netmask: '255.255.255.0'
dhcp_router_ip: '10.10.5.1'
```

SSH Keys are defined for the users to provide easy access to all nodes and
future VMs in the Ansible *vault* file with the following 'dict' syntax:
```yaml
---
system_ssh_ids:
  tdh:
    ssh_id: ''
  tarland:
    ssh_id: ''
```

This file is stored encrypted via `ansible-vault encrypt $file` in the
inventory path of **inventory/$env/group_vars/all/vault**.


### Inventory Host Groups

The inventory for hosts falls into 4 groups, *mgmt_server*, *kvm_nodes*
(the KVM cluster nodes), and optional *nfs_server* and *nfs_client* groups 
for configuring NFS-based secondary storage.
```ini
[kvm_nodes]
dil[01:08]

[nfs_server]
dis01

[nfs_client]
dil[01:08]

[mgmt_server]
dim01
```


## Roles

- **kvm-qemu**: Consists of a `nodes` group defining the list of hosts that
  will run a KVM Hypervisor. An additional host group of `nfs_server` will
  create the NFS share for use as a secondary storage pool.

- **mgmt-server**: Installs our kvm management tools and prerequisites such
  as *dnsmasq*.

- **nfs-common**: Installs NFS requirements common to both server and client.

- **nfs-server**: Creates the secondary storage NFS mount and configures
  the NFS Server to serve the mount.

- **nfs-client**: Configures client nodes for mounting the NFS secondary
  storage.


## Adding users

To add new users, adjust the inventory *group_vars/all.yml* to reflect
the new user and user group. It is important to verify that the uid:gid 
chosen are in fact available and not already in use across nodes. The new 
settings can be applied via the common role.


## Running Ansible playbooks

Deploy KVM-QEMU hypervisor across nodes.
```sh
ansible-playbook -i inventory/tdh-west1/hosts kvm-qemu.yml
```

Install the management tools.
```sh
ansible-playbook -i inventory/tdh-west1/hosts kvm-mgr.yml
```
