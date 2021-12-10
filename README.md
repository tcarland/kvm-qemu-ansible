kvm-qemu-ansible
=================

  Ansible playbooks and scripts for installing and managing a multi-node 
KVM-QEMU environment on Linux systems. 

  The Ansible roles do not configure local storage or networking for KVM, 
but do provide roles for utilizing NFS as a secondary storage pool. 
Local-attached storage is as the primary storage pool for VM images.
A bridge network for VM connectivity is also a requirement.  Both 
of these topics are discussed in the prerequisites document, followed by 
the Ansible Deployment Guide and the KVM Operational guides.

 - [01-prerequisites.md](docs/01-prerequisites.md)

 - [02-kvm-ansible.md](docs/02-kvm-ansible.md)

 - [03-kvm-operations.md](docs/03-kvm-operations.md)

The docs can be converted to PDF by running `make docs`.