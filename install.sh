#!/usr/bin/env bash
# OpenShift Virtualisation Labs Install Script
# Rhys Oxenham <roxenham@redhat.com>

# Set location of SSH public key you want to use for the bastion VM
SSH_PUB_BASTION=~/.ssh/id_rsa.pub

# Set your pull secret json (see https://cloud.redhat.com/openshift/install)
PULL_SECRET=''

# Set the version of OpenShift you want to deploy
# You can use a specific release, e.g. 4.6.1, or use latest-4.5, latest-4.6 (default), etc.
# Check available versions here: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
OCP_VERSION=latest-4.6

# Set the RHEL8 or CentOS8 image you will use for the bastion VM
# This image will be cached in /var/lib/libvirt/images if you've already got one
RHEL8_KVM=https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2

# Configure if you want to be able to support OpenShift Container Storage (3rd worker + extra volumes) - default is FALSE
OCS_SUPPORT=false

# Configure if you want to use a disconnected registry to save bandwidth and speed up deployment - default is TRUE
USE_DISCONNECTED=true

# Configure if you want to use Baremetal IPI mode instead of UPI (requires 4.6) - default is FALSE
# WARNING: This code is experimental and has not been extensively tested on EL8.
USE_IPI=false

################################
# DO NOT CHANGE ANYTHING BELOW #
################################

if [[ "$OCP_VERSION" == *"latest"* ]]
then
    SUBVER=`echo "${OCP_VERSION}" | cut -d- -f2`
else
    SUBVER=`echo "${OCP_VERSION:0:3}"`
fi

OCP_INSTALL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-install-linux.tar.gz
OC_CLIENT=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/openshift-client-linux.tar.gz

mkdir -p pxeboot/generated
cp pxeboot/C* pxeboot/default pxeboot/generated

if [ $SUBVER = "4.5" ]
then
    RHCOS_RAMDISK=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-installer-initramfs.x86_64.img
    RHCOS_KERNEL=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-installer-kernel-x86_64
else
    RHCOS_RAMDISK=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-live-initramfs.x86_64.img
    RHCOS_KERNEL=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-live-kernel-x86_64

    # Remove the coreos.inst.image_url entry as it causes a boot conflict on >=4.6
    sed -i "s|coreos.inst.image_url=http://192.168.123.100:81/rhcos.raw.gz||g" pxeboot/generated/*
fi

RHCOS_RAW=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-metal.x86_64.raw.gz
RHCOS_ROOTFS=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$SUBVER/latest/rhcos-live-rootfs.x86_64.img

echo "=============================================="
echo "OpenShift Virtualisation Lab Deployment Script"
echo -e "==============================================\n"

echo -e "[INFO] Requested deployment version: OpenShift $OCP_VERSION\n"

echo -e "[INFO] Checking if your pull secret is VALID (won't check if authorised)...\n"
if [ -z "$PULL_SECRET" ]
then
	echo -e "[ERROR] Your PULL_SECRET variable is empty, you need to configure this.\n"
	exit 1
fi

if ! command -v jq &> /dev/null
then
	echo -n "[WARNING] We use jq to validate your PULL_SECRET, but it's not installed. We can proceed at your own risk or Ctrl-C and install jq first. (Sleeping 10s)"
	sleep 10
else

	if jq -e . >/dev/null 2>&1 <<<"$PULL_SECRET"
	then
		echo -e "[INFO] Your pull secret appears to be formatted correctly."
	else
		echo -e "[ERROR] Your pull secret could not be parsed by jq, please re-check!\n"
		exit 1
	fi
fi

MINORVER=`echo "${SUBVER}" | cut -d. -f2`
if [ $MINORVER -le 5 ] && $USE_IPI
then
    echo -e "\n[ERROR] To use the Baremetal IPI mode you need to use (at least) OpenShift 4.6.0.\n"
    exit 1
fi

echo -e "\n\n[INFO] Checking if CoreOS and OpenShift image locations are accessible...\n"

if [ $SUBVER = "4.5" ]
then
    echo -e "[INFO] Skipping RHCOS RootFS Download (not required prior to 4.6)\n"
else
    echo -n "Checking: $RHCOS_ROOTFS - "
    if curl --output /dev/null --silent --head --fail $RHCOS_ROOTFS
    then
        echo "[OK]"
    else
        echo "[FAIL]"
        echo -e "\n\n[ERROR] Failed to deploy due to inaccessible image locations"
        exit 1
    fi
fi

for i in $RHCOS_RAW $RHCOS_KERNEL $RHCOS_RAMDISK $OCP_INSTALL $OC_CLIENT $RHEL8_KVM
do
	echo -n "Checking: $i - "
	if curl --output /dev/null --silent --head --fail $i
	then
		echo "[OK]"
	else
		echo "[FAIL]"
		echo -e "\n\n[ERROR] Failed to deploy due to inaccessible image locations"
		exit 1
	fi
done

LOW_MEMORY=false
echo -e "\n[INFO] Checking system for available memory...\n"
if [[ 100 -ge $(free -g | awk '/Mem/ {print $2;}') ]]; then
	echo -e "\n[WARN] This system doesn't have the optimum amount of memory and your mileage may vary!\n\n\n"
	sleep 10
	LOW_MEMORY=true
fi

echo -e "\n\n[INFO] Installing necessary packages on the hypervisor...\n"
sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo dnf -y install wget libvirt qemu-kvm virt-manager virt-install libguestfs libguestfs-tools libguestfs-xfs net-tools sshpass virt-what nmap

EL8=false
if hostnamectl | egrep -i '(red|cent)'> /dev/null 2>&1
then
	EL8=true
fi

if $EL8 && $USE_IPI
then
	echo -e "\n\n[INFO] Enabling OpenStack package repos for VirtualBMC...\n"
	dnf install https://www.rdoproject.org/repos/rdo-release.el8.rpm -y
	dnf install python36 -y
fi

if $USE_IPI
then
	sudo dnf install python3-virtualbmc -y
	if $EL8
	then
		sudo systemctl enable --now virtualbmc
	else
		sudo systemctl enable --now vbmcd
	fi
fi

echo -e "\n\n[INFO] Defining the dedicated libvirt network (192.168.123.0/24)...\n"

sudo modprobe tun
sudo systemctl enable --now libvirtd
sudo virsh net-define configs/ocp4-net.xml
sudo virsh net-start ocp4-net
sudo virsh net-autostart ocp4-net

if $USE_IPI
then
	sudo virsh net-define configs/ipi/ocp4-prov-net.xml
	sudo virsh net-start ocp4-provisioning
	sudo virsh net-autostart ocp4-provisioning
fi

echo -e "\n[INFO] Creating the disk images for the OpenShift nodes...\n"

for i in bootstrap master1 master2 master3 worker1 worker2 worker3
do
	sudo qemu-img create -f qcow2 /var/lib/libvirt/images/ocp4-$i.qcow2 80G
done

echo -e "\n\n[INFO] Downloading and customising the RHEL8 KVM guest image to become bastion host...\n"

if [ ! -f /var/lib/libvirt/images/rhel8-kvm.qcow2 ]; then
    sudo wget -O /var/lib/libvirt/images/rhel8-kvm.qcow2 $RHEL8_KVM
fi

if [ ! -f /var/lib/libvirt/images/rhel8-kvm.qcow2 ]; then
    echo -e "\n\n[ERROR] Failed to deploy due to missing rhel8-kvm.qcow2 file"
    exit 1
fi

sudo qemu-img create -f qcow2 /var/lib/libvirt/images/ocp4-bastion.qcow2 -b /var/lib/libvirt/images/rhel8-kvm.qcow2 -F qcow2 200G
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --uninstall cloud-init
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --root-password password:redhat
sudo -E virt-copy-in -a /var/lib/libvirt/images/ocp4-bastion.qcow2 configs/ifcfg-eth0 /etc/sysconfig/network-scripts
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --run-command "mkdir -p /root/.ssh/ && chmod -R 0700 /root/.ssh/"
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --run-command "restorecon -Rv /root/.ssh/"

echo -e "\n\n[INFO] Defining empty storage containers for OCS (even if not used)...\n"
for i in 1 2 3; do
        for j in 1 2; do
                sudo qemu-img create -f qcow2 /var/lib/libvirt/images/ocp4-worker$i-osd$j.qcow2 100G
        done
done

echo -e "\n\n[INFO] Setting the OpenShift virtual machine definitions in libvirt...\n"

CPU_FLAGS="--cpu=host-passthrough"

WORKER_MEMORY=32768
BASTION_MEMORY=16384
if $LOW_MEMORY; then
	WORKER_MEMORY=16384
	BASTION_MEMORY=8192
fi

if $USE_IPI; then
	BAST_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:00"
	M1_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:01"
	M2_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:02"
	M3_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:03"
	W1_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:04"
	W2_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:05"
	W3_PROV="--network network:ocp4-provisioning,mac=de:ad:be:ef:00:06"
fi

mkdir -p node-configs/
sudo virt-install --virt-type kvm --ram $BASTION_MEMORY --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-bastion.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:22:33:44 $BAST_PROV --boot hd --name ocp4-bastion --print-xml 1 > node-configs/ocp4-bastion.xml
sudo virt-install --virt-type kvm --ram 8192 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-bootstrap.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:33:44:55 --boot hd,network --name ocp4-bootstrap --print-xml 1 > node-configs/ocp4-bootstrap.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master1.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $M1_PROV --network network:ocp4-net,mac=52:54:00:19:d7:9c --boot hd,network --name ocp4-master1 --print-xml 1 > node-configs/ocp4-master1.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $M2_PROV --network network:ocp4-net,mac=52:54:00:60:66:89 --boot hd,network --name ocp4-master2 --print-xml 1 > node-configs/ocp4-master2.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master3.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $M3_PROV --network network:ocp4-net,mac=52:54:00:9e:5c:3f --boot hd,network --name ocp4-master3 --print-xml 1 > node-configs/ocp4-master3.xml
sudo virt-install --virt-type kvm --ram $WORKER_MEMORY --vcpus 16 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-worker1.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker1-osd1.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker1-osd2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $W1_PROV --network network:ocp4-net,mac=52:54:00:47:4d:83 --network network:ocp4-net,mac=52:54:00:47:5e:94 --boot hd,network --name ocp4-worker1 --print-xml 1 > node-configs/ocp4-worker1.xml
sudo virt-install --virt-type kvm --ram $WORKER_MEMORY --vcpus 16 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-worker2.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker2-osd1.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker2-osd2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $W2_PROV --network network:ocp4-net,mac=52:54:00:b2:96:0e --network network:ocp4-net,mac=52:54:00:47:ad:1f --boot hd,network --name ocp4-worker2 --print-xml 1 > node-configs/ocp4-worker2.xml
sudo virt-install --virt-type kvm --ram $WORKER_MEMORY --vcpus 16 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-worker3.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker3-osd1.qcow2,device=disk,bus=virtio,format=qcow2 --disk path=/var/lib/libvirt/images/ocp4-worker3-osd2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc $W3_PROV --network network:ocp4-net,mac=52:54:00:b2:21:66 --network network:ocp4-net,mac=52:54:00:41:be:22 --boot hd,network --name ocp4-worker3 --print-xml 1 > node-configs/ocp4-worker3.xml

for i in bastion bootstrap master1 master2 master3 worker1 worker2 worker3
do
	sudo virsh define node-configs/ocp4-$i.xml
done

if $USE_IPI; then
	echo -e "\n[INFO] Setting up for an IPI based installation...\n"
	counter=1
	FIREWALLD=false
	if sudo systemctl status firewalld 2>&1 >/dev/null
	then
		FIREWALLD=true
	fi
	for i in master1 master2 master3 worker1 worker2 worker3
	do
		sudo vbmc add --username admin --password redhat --port 623$counter --address 192.168.123.1 --libvirt-uri qemu:///system ocp4-$i
		sudo vbmc start ocp4-$i
		if $FIREWALLD
		then
			sudo firewall-cmd --add-port 623$counter/udp --zone libvirt --permanent
		else
			sudo iptables -A LIBVIRT_INP -p udp --dport 623$counter -j ACCEPT
		fi
		counter=$((counter + 1))
	done
	if $FIREWALLD; then sudo firewall-cmd --reload; fi
	sudo vbmc list
fi

echo -e "\n[INFO] Starting the bastion host and copying in our ssh keypair...\n"

if [ ! -f $SSH_PUB_BASTION ]; then
    ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
    SSH_PUB_BASTION=~/.ssh/id_rsa.pub
fi

sudo virsh start ocp4-bastion
#sleep 60
echo -ne "\n[INFO] Waiting for the ssh daemon on the bastion host to appear"
while [ ! "`nmap -sV -p 22 192.168.123.100|grep open`" ]; do
  echo -n "."
  sleep 1s
done
echo

sed -i /192.168.123.100/d ~/.ssh/known_hosts
sshpass -p redhat ssh-copy-id -o StrictHostKeyChecking=no -i $SSH_PUB_BASTION root@192.168.123.100

cat <<EOF > bastion-deploy.sh
hostnamectl set-hostname ocp4-bastion.cnv.example.com
dnf install qemu-img jq git httpd squid dhcp-server xinetd net-tools nano bind bind-utils haproxy wget syslinux libvirt-libs -y
dnf install tftp-server syslinux-tftpboot -y
dnf update -y
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
dnf install firewalld -y
systemctl enable --now firewalld
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --add-service=dns --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-service=squid --permanent
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-service={nfs3,mountd,rpc-bind} --permanent
firewall-cmd --add-service=nfs --permanent
firewall-cmd --permanent --add-port 6443/tcp
firewall-cmd --permanent --add-port 8443/tcp
firewall-cmd --permanent --add-port 22623/tcp
firewall-cmd --permanent --add-port 81/tcp
firewall-cmd --reload
setsebool -P haproxy_connect_any=1
mkdir -p /nfs/pv1
mkdir -p /nfs/pv2
mkdir -p /nfs/fc31
chmod -R 777 /nfs
echo -e "/nfs *(rw,no_root_squash)" > /etc/exports
# we may have to do something about setting /etc/nfs.conf to v4 only
systemctl enable httpd
systemctl enable named
systemctl enable squid
systemctl enable dhcpd
systemctl enable rpcbind
systemctl enable nfs-server
mkdir -p /var/lib/tftpboot/pxelinux/pxelinux.cfg/
cp -f /tftpboot/pxelinux.0 /var/lib/tftpboot/pxelinux
cp -f /tftpboot/ldlinux.c32 /var/lib/tftpboot/pxelinux
cp -f /tftpboot/vesamenu.c32 /var/lib/tftpboot/pxelinux
sed -i 's/Listen 80/Listen 81/g' /etc/httpd/conf/httpd.conf
wget $OCP_INSTALL
wget $OC_CLIENT
tar -zxvf openshift-client*
tar -zxvf openshift-install*
cp oc kubectl /usr/bin/
rm -f oc kubectl
chmod a+x /usr/bin/oc
chmod a+x /usr/bin/kubectl
mkdir -p /root/ocp-install/
growpart /dev/vda 1
xfs_growfs /
EOF

if $USE_IPI; then
	sed -i /tftp/d bastion-deploy.sh
	cat <<EOF >> bastion-deploy.sh
	dnf install -y libvirt qemu-kvm mkisofs python3-devel jq ipmitool
	systemctl enable --now libvirtd
	virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
	virsh pool-start default
	virsh pool-autostart default
	nmcli connection add ifname provisioning type bridge con-name provisioning
	nmcli con add type bridge-slave ifname eth1 master provisioning
	nmcli connection modify provisioning ipv4.addresses 172.22.0.1/24 ipv4.method manual
	nmcli connection modify provisioning ipv4.gateway 172.22.0.254
	nmcli con down provisioning
	nmcli con up provisioning
	nmcli connection add ifname baremetal type bridge con-name baremetal
	nmcli con add type bridge-slave ifname eth0 master baremetal
	nmcli con down "System eth0"
	nmcli connection modify baremetal ipv4.addresses 192.168.123.100/24 ipv4.method manual
	nmcli connection modify baremetal ipv4.gateway 192.168.123.1
	nmcli con down baremetal
	nmcli con up baremetal
	rm -f /etc/sysconfig/network-scripts/ifcfg-eth0
EOF

else
	cat <<EOF >> bastion-deploy.sh
	systemctl enable xinetd
	systemctl enable tftp
	systemctl enable haproxy
	wget $RHCOS_RAW
	wget $RHCOS_KERNEL
	wget $RHCOS_RAMDISK
	wget $RHCOS_ROOTFS
	mv rhcos* /var/www/html
	mv /var/www/html/*raw* /var/www/html/rhcos.raw.gz
	mv /var/www/html/*kernel* /var/www/html/rhcos.kernel
	mv /var/www/html/*initramfs* /var/www/html/rhcos.initramfs
	mv /var/www/html/*rootfs* /var/www/html/rhcos.rootfs
	chmod -R 777 /var/www/html
	restorecon -Rv /var/www/html
EOF
fi

echo -e "\n\n[INFO] Running the bastion deployment script remotely...\n"

scp -o StrictHostKeyChecking=no bastion-deploy.sh root@192.168.123.100:/root/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 sh /root/bastion-deploy.sh
ssh -o StrictHostKeyChecking=no root@192.168.123.100 rm -f /root/bastion-deploy.sh

echo -e "\n\n[INFO] Copying the RHEL8 KVM Image into the guest...\n"
scp -o StrictHostKeyChecking=no /var/lib/libvirt/images/rhel8-kvm.qcow2 root@192.168.123.100:/var/www/html/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "qemu-img convert -f qcow2 -O raw /var/www/html/rhel8-kvm.qcow2 /var/www/html/rhel8-kvm.img"

echo -e "\n\n[INFO] Configuring the supporting services (squid, haproxy, DNS, DHCP, TFTP, httpd)...\n"

if $USE_IPI; then
	scp -o StrictHostKeyChecking=no configs/ipi/dhcpd.conf root@192.168.123.100:/etc/dhcp/dhcpd.conf
	scp -o StrictHostKeyChecking=no configs/ipi/cnv.example.com.db root@192.168.123.100:/var/named/cnv.example.com.db
	cp -f configs/ipi/install-config.yaml pre-install-config.yaml
	if $OCS_SUPPORT; then
		# We default to 3 masters anyway, so we can force all replica counts to 3 safely
		sed -i 's/replicas:.*/replicas: 3/g' pre-install-config.yaml
	fi
else
	scp -o StrictHostKeyChecking=no configs/dhcpd.conf root@192.168.123.100:/etc/dhcp/dhcpd.conf
	cp -f configs/install-config.yaml pre-install-config.yaml
	scp -o StrictHostKeyChecking=no -r pxeboot/generated/* root@192.168.123.100:/var/lib/tftpboot/pxelinux/pxelinux.cfg/
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "restorecon -Rv /var/lib/tftpboot/ && chmod -R 777 /var/lib/tftpboot/pxelinux"
	scp -o StrictHostKeyChecking=no configs/cnv.example.com.db root@192.168.123.100:/var/named/cnv.example.com.db
fi

scp -o StrictHostKeyChecking=no configs/squid.conf root@192.168.123.100:/etc/squid/squid.conf
scp -o StrictHostKeyChecking=no configs/named.conf root@192.168.123.100:/etc/named.conf
scp -o StrictHostKeyChecking=no configs/haproxy.cfg root@192.168.123.100:/etc/haproxy/haproxy.cfg
scp -o StrictHostKeyChecking=no configs/123.168.192.db root@192.168.123.100:/var/named/123.168.192.db

sed -i "s/PULL_SECRET/$PULL_SECRET/g" pre-install-config.yaml
scp -o StrictHostKeyChecking=no pre-install-config.yaml root@192.168.123.100:/root/install-config.yaml

ssh -o StrictHostKeyChecking=no root@192.168.123.100 'sed -i "s|BAST_SSHKEY|$(cat /root/.ssh/id_rsa.pub)|g" install-config.yaml'
ssh -o StrictHostKeyChecking=no root@192.168.123.100 cp /root/install-config.yaml /root/ocp-install/install-config.yaml

if $USE_DISCONNECTED; then
    echo -e "\n\n[INFO] Deploying the disconnected image registry...\n"
    scp -o StrictHostKeyChecking=no scripts/deploy-disconnected.sh root@192.168.123.100:/root/
    echo $PULL_SECRET > /tmp/secret
    scp -o StrictHostKeyChecking=no /tmp/secret root@192.168.123.100:~/pull-secret.json
    rm /tmp/secret -f
    ssh -o StrictHostKeyChecking=no root@192.168.123.100 sh /root/deploy-disconnected.sh
fi

echo -e "\n\n[INFO] Rebooting bastion host...\n"

ssh -o StrictHostKeyChecking=no root@192.168.123.100 reboot

echo -ne "\n[INFO] Waiting for the ssh daemon on the bastion host to appear"
while [ ! "`nmap -sV -p 22 192.168.123.100|grep open`" ]; do
  echo -n "."
  sleep 1s
done
echo

if $USE_DISCONNECTED; then
    sleep 30
    ssh -o StrictHostKeyChecking=no root@192.168.123.100 podman start poc-registry
fi

mkdir -p generated/
mv bastion-deploy.sh pre-install-config.yaml generated/

sleep 1m

ssh -o StrictHostKeyChecking=no root@192.168.123.100 'echo -e "search cnv.example.com\nnameserver 192.168.123.100" > /etc/resolv.conf && chattr +i /etc/resolv.conf'

if $USE_IPI; then
	scp -o StrictHostKeyChecking=no scripts/rhcos-refresh.sh root@192.168.123.100:~
	echo -e "\n\n[INFO] Extracting the OpenShift Baremetal Installer binary...\n"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "oc adm release extract --registry-config ~/pull-secret.json --command=openshift-baremetal-install --to /root \$(oc version | awk '/Client/ {print \$3;}')"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-baremetal-install version"
	echo -e "\n\n[INFO] Grabbing the latest RHCOS images for the specified OpenShift version...\n"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 cp /root/install-config.yaml /root/ocp-install/install-config.yaml
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "sh ~/rhcos-refresh.sh"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-baremetal-install --dir=/root/ocp-install/ create manifests"
	scp -o StrictHostKeyChecking=no configs/ocp/99* root@192.168.123.100:/root/ocp-install/openshift/
	echo -e "\n\n[INFO] Running OpenShift IPI Installation (nodes will boot automatically)...\n"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-baremetal-install --dir=/root/ocp-install --log-level=debug create cluster"
	# Sometimes this can timeout on a slower system so adding in an extra 1hr to the timeout
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-baremetal-install --dir=/root/ocp-install --log-level=debug wait-for install-complete"
else
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install/ create manifests"
	scp -o StrictHostKeyChecking=no configs/ocp/99* root@192.168.123.100:/root/ocp-install/openshift/
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 cp /root/install-config.yaml /root/ocp-install/install-config.yaml
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install/ create ignition-configs"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "cp /root/ocp-install/*.ign /var/www/html/ && restorecon -Rv /var/www/html && chmod -R 777 /var/www/html"

	echo -e "\n\n[INFO] Booting OpenShift nodes (they'll PXE boot automatically)...\n"
	for i in bootstrap master1 master2 master3 worker1 worker2
	do
		sudo virsh start ocp4-$i
	done

	if $OCS_SUPPORT; then
		sudo virsh start ocp4-worker3
	fi

	sleep 20

	echo -e "\n\n[INFO] Waiting for OpenShift installation to complete...\n"

	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install wait-for bootstrap-complete"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install wait-for bootstrap-complete" > /tmp/bootstrap-test 2>&1
	grep safe /tmp/bootstrap-test > /dev/null 2>&1
	if [ "$?" -ne 0 ]
	then
		echo -e "\n\n\nERROR: Bootstrap did not complete in time!"
		echo "Your environment (CPU or network bandwidth) might be"
		echo "too slow. Continue by hand or execute ./cleanup.sh and"
		echo "start all over again."
		exit 1
	fi

	echo -e "\n\n[INFO] Completing the installation and approving workers...\n"
	sudo virsh destroy ocp4-bootstrap
	sleep 300
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && for csr in \$(oc -n openshift-machine-api get csr | awk '/Pending/ {print \$1}'); do oc adm certificate approve \$csr;done"
	sleep 180
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && for csr in \$(oc -n openshift-machine-api get csr | awk '/Pending/ {print \$1}'); do oc adm certificate approve \$csr;done"
	ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install wait-for install-complete --log-level=debug"
fi

echo -e "\n\n[INFO] Enabling the Image Registry on NFS...\n"

ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\":{\"managementState\":\"Managed\"}}'"
scp -o StrictHostKeyChecking=no configs/image-registry-pv.yaml root@192.168.123.100:/root/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc create -f image-registry-pv.yaml"
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\":{\"storage\":{\"pvc\":{}}}}'"

# Restart squid, as it doesn't come up properly FIXME
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "systemctl restart squid"

echo -e "\n\n[INFO] Approving any worker CSRs that have not yet been approved..."
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && for csr in \$(oc -n openshift-machine-api get csr | awk '/Pending/ {print \$1}'); do oc adm certificate approve \$csr;done"

echo -e "\n\n[INFO] Waiting for the cluster to settle and all pods start up..."
sleep 180

# These next steps are optional - move the exit above if you don't want to deploy them - TODO create variable

# Deploy the CNV/bookbag service
echo -e "\n\n[INFO] Deploying the Hands-on Lab Guide..."
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc new-project workbook"
sleep 10
scp -o StrictHostKeyChecking=no -rq docs root@192.168.123.100:/root/
sleep 10
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc process -f docs/build-template.yaml -p NAME=cnv | oc apply -f -"
sleep 30
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && for csr in \$(oc -n openshift-machine-api get csr | awk '/Pending/ {print \$1}'); do oc adm certificate approve \$csr;done"
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc start-build cnv --from-dir=./docs/"
sleep 75

# Check progress on the build
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc get pods|grep \"^cnv-.-build\""|grep "Init:Error"
if [ "$?" -eq 0 ]; then
    echo -e "\n\n[INFO] Something went wrong... retrying once\n"
    sleep 75
    ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && for csr in \$(oc -n openshift-machine-api get csr | awk '/Pending/ {print \$1}'); do oc adm certificate approve \$csr;done"
    ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc start-build cnv --from-dir=./docs/"
    sleep 75
fi

ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc process -f docs/deploy-template.yaml -p NAME=cnv -p IMAGE_STREAM_NAME=cnv | oc apply -f -"

# Enable cluster-admin privileges for the cnv/bookbag user
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc adm policy add-cluster-role-to-user cluster-admin -z cnv"

echo -e "\n\n[SUCCESS] Deployment has been succesful!"

exit 0
