KVM Ansible Deployment Guide
============================

  Ansible is used to bootstrap systems as well as optionally install the
KVM stack and NFS Server/Clients.

  Prior to running the Ansible Playbooks, the base storage systems to be used for
the primary storage pool (and optional NFS Server) should already be created and
mounted as well as the bridged network configured.

  The following inventory settings from *inventory/$env/group_vars/all/vars*
should be customized to provide the domain settings, storage locations, and IP
Address ranges. The following inventory example uses a common role-account called
*tdh* for managing KVM and is added to the three primary groups needed.

**inventory/$env/group_vars/all/vars**
```
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
future VMs in the *vault* file with the following 'dict' syntax:
```
---
system_ssh_ids:
  tdh:
    ssh_id: ''
  tarland:
    ssh_id: ''
```

## Inventory

The inventory for hosts falls into 4 groups, *mgmt_server*, *kvm_nodes*
(the KVM cluster nodes), and optional *nfs_server* and *nfs_client* groups for
configuring NFS-based secondary storage.
```
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

- **common**:  System bootstrapping common to all systems. Intended to be
  applied first to bootstrap accounts and packages with more specific roles
  or playbooks running after. While it may be idempotent, it does provide base
  system configs that may have been overwritten by app specific playbooks ran
  after. Most importantly, this role is used to distribute users and ssh keys.

- **kvm-qemu**: Consists of a `nodes` group defining the list of hosts that
  will run a KVM Hypervisor. An additional host group of `nfs_server` will
  create the NFS share for use as a secondary storage pool.


## Adding users

  To add new users, adjust the inventory *group_vars/all.yml* to reflect
the new user and user group. It is important to verify that the uid:gid chosen
are in fact available and not already in use across nodes. The new settings
can be reapplied via the common role.


## Running the Ansible playbooks

Running a complete environment install (which includes the common role)
```
ansible-playbook -i inventory/itc-sv04/hosts kvm-qemu.yml
```

Running a user update via common playbook.
```
ansible-playbook -i inventory/itc-sv04/hosts common.yml
```
