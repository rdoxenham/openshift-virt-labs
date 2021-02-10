#!/usr/bin/env bash
# OpenShift Virtualisation Labs Cleanup Script

for i in master1 master2 master3 worker1 worker2 worker3 bastion bootstrap
do
	sudo virsh destroy ocp4-$i
	sudo virsh undefine ocp4-$i
	sudo rm -f /var/lib/libvirt/images/ocp4-$i.qcow2
	sudo rm -f /var/lib/libvirt/images/ocp4-$i-osd1.qcow2
	sudo rm -f /var/lib/libvirt/images/ocp4-$i-osd2.qcow2
done

if sudo systemctl status vbmcd 2>&1 >/dev/null || sudo systemctl status virtualbmc 2>&1 >/dev/null
then
	for i in master1 master2 master3 worker1 worker2 worker3
	do
		sudo vbmc delete ocp4-$i
	done

	sudo rm -rf /var/lib/vbmcd/.vbmc

	if sudo systemctl status firewalld 2>&1 >/dev/null
	then
		for i in {1..6}
		do
			sudo firewall-cmd --remove-port 623$i/udp --zone libvirt --permanent
		done
		sudo firewall-cmd --reload
	else
		for i in {1..6}
		do
			sudo iptables -D LIBVIRT_INP -p udp --dport 623$i -j ACCEPT
		done
	fi

	sudo systemctl disable --now vbmcd
	sudo systemctl disable --now virtualbmc
fi

sudo rm -rf pxeboot/generated
sudo rm -f node-configs/*
sudo rm -rf generated/

sudo virsh net-destroy ocp4-net
sudo virsh net-undefine ocp4-net

sudo virsh net-destroy ocp4-provisioning
sudo virsh net-undefine ocp4-provisioning
