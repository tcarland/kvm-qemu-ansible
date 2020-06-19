kvm-qemu-ansible
=================

  Ansible playbooks and scripts for installing and managing KVM-QEMU on
either RHEL/Centos or Ubuntu Linux systems. This is intended for deploying
KVM across a cluster of nodes. The Ansible roles do not configure storage or
networking, but there are NFS roles included for utilizing NFS for a secondary
storage pool.

  The networking layer for a bridge network to be used by Virtual Machines is
also a prerequisite.  Both of these topics are discussed in the first
document:

docs/00-initial-setup-guide.md  [docs/00-initial-setup-guide.md]
