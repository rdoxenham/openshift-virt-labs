#!/usr/bin/env bash
# KubeVirt Labs Cleanup Script

for i in master1 master2 master3 worker1 worker2 worker3 bastion bootstrap
do
	sudo virsh destroy ocp4-$i
	sudo virsh undefine ocp4-$i
done

sudo rm -f node-configs/*
sudo rm -rf generated/

sudo rm -f /var/lib/libvirt/images/ocp4*.qcow2

sudo virsh net-destroy ocp4-net
sudo virsh net-undefine ocp4-net
