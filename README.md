kvm-qemu-ansible
=================

Copyright (c)2015-2026 Timothy C. Arland <tcarland at gmail dot com>

Ansible playbooks and scripts for installing and managing a distributed, 
multi-node KVM-QEMU environment on Linux systems. 

The Ansible roles do not configure local storage or networking for KVM, 
but do provide roles for utilizing NFS as a secondary storage pool. 
Local-attached storage is intended to be the primary storage pool for 
active kvm images. A bridge network for cluster connectivity is a 
requirement.  

These topics are discussed in the prerequisites, followed by 
the Ansible Deployment Guide and the KVM Operational guides under 
our *docs/* directory. Use the `make docs` command to build the 
HTML site.

 - [01-prerequisites.md](01-prerequisites.md)

 - [02-kvm-ansible.md](02-kvm-ansible.md)

 - [03-kvm-operations.md](03-kvm-operations.md)
