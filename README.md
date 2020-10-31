kvm-qemu-ansible
=================

  Ansible playbooks and scripts for installing and managing KVM-QEMU 
on either RHEL/Centos or Ubuntu Linux systems. This is intended for 
deploying KVM across a cluster of nodes. 

  The Ansible roles do not configure storage or networking, but there 
are NFS roles included for utilizing NFS for a secondary storage pool.

  A bridge network for VM connectivity is also a prerequisite.  Both 
of these topics are discussed in the first document, followed by the 
deployment and operational guides.

 - [01-prerequisites.md](docs/01-prerequisites.md)

 - [02-kvm-ansible.md](docs/02-kvm-ansible.md)

 - [03-kvm-operations.md](docs/03-kvm-operations.md)


  The docs can be converted to pdf by running `make docs`.