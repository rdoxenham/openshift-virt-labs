#!/usr/bin/env bash
# OpenShift virtualisation Labs Install Script
# Rhys Oxenham <roxenham@redhat.com>

# Set location of SSH key you want to use for bastion
SSH_PUB_BASTION=~/.ssh/id_rsa.pub

# Set your pull secret json (cloud.redhat.com; more directly at https://cloud.redhat.com/openshift/install)
PULL_SECRET=''

# Set the locations of the images you want to use...
RHCOS_RAMDISK=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.5/latest/rhcos-4.5.2-x86_64-installer-initramfs.x86_64.img
RHCOS_KERNEL=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.5/latest/rhcos-4.5.2-x86_64-installer-kernel-x86_64
RHCOS_RAW=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.5/latest/rhcos-4.5.2-x86_64-metal.x86_64.raw.gz
OCP_INSTALL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.5/openshift-install-linux.tar.gz
OC_CLIENT=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.5/openshift-client-linux.tar.gz

# You will need either a RHEL8 or CentOS8 image
RHEL8_KVM=https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2

echo "=============================="
echo "KubeVirt Lab Deployment Script"
echo -e "==============================\n"

echo -e "[INFO] Checking if CoreOS and OpenShift image locations are accessible...\n"
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

echo -e "\n\n[INFO] Installing necessary packages on the hypervisor...\n"
sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo dnf -y install wget libvirt qemu-kvm virt-manager virt-install libguestfs libguestfs-tools libguestfs-xfs net-tools sshpass virt-what nmap

echo -e "\n\n[INFO] Defining the dedicated libvirt network (192.168.123.0/24)...\n"

sudo modprobe tun
sudo systemctl enable --now libvirtd
sudo virsh net-define configs/ocp4-net.xml
sudo virsh net-start ocp4-net
sudo virsh net-autostart ocp4-net

echo -e "\n[INFO] Creating the disk images for the OpenShift nodes...\n"

for i in bootstrap master1 master2 master3 worker1 worker2
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

sudo qemu-img create -f qcow2 /var/lib/libvirt/images/ocp4-bastion.qcow2 -b /var/lib/libvirt/images/rhel8-kvm.qcow2 200G
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --uninstall cloud-init
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --root-password password:redhat
sudo -E virt-copy-in -a /var/lib/libvirt/images/ocp4-bastion.qcow2 configs/ifcfg-eth0 /etc/sysconfig/network-scripts
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --run-command "mkdir -p /root/.ssh/ && chmod -R 0700 /root/.ssh/"
sudo -E virt-customize -a /var/lib/libvirt/images/ocp4-bastion.qcow2 --run-command "restorecon -Rv /root/.ssh/"

echo -e "\n\n[INFO] Setting the OpenShift virtual machine definitions in libvirt...\n"

CPU_FLAGS="--cpu=host-passthrough"

mkdir -p node-configs/
sudo virt-install --virt-type kvm --ram 4096 --vcpus 2 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-bastion.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:22:33:44 --boot hd,network --name ocp4-bastion --print-xml 1 > node-configs/ocp4-bastion.xml
sudo virt-install --virt-type kvm --ram 8192 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-bootstrap.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:33:44:55 --boot hd,network --name ocp4-bootstrap --print-xml 1 > node-configs/ocp4-bootstrap.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master1.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:19:d7:9c --boot hd,network --name ocp4-master1 --print-xml 1 > node-configs/ocp4-master1.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:60:66:89 --boot hd,network --name ocp4-master2 --print-xml 1 > node-configs/ocp4-master2.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 4 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-master3.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:9e:5c:3f --boot hd,network --name ocp4-master3 --print-xml 1 > node-configs/ocp4-master3.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 8 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-worker1.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:47:4d:83 --network network:ocp4-net,mac=52:54:00:47:5e:94 --boot hd,network --name ocp4-worker1 --print-xml 1 > node-configs/ocp4-worker1.xml
sudo virt-install --virt-type kvm --ram 16384 --vcpus 8 --os-variant rhel8.1 --disk path=/var/lib/libvirt/images/ocp4-worker2.qcow2,device=disk,bus=virtio,format=qcow2 $CPU_FLAGS --noautoconsole --vnc --network network:ocp4-net,mac=52:54:00:b2:96:0e --network network:ocp4-net,mac=52:54:00:47:ad:1f --boot hd,network --name ocp4-worker2 --print-xml 1 > node-configs/ocp4-worker2.xml

for i in bastion bootstrap master1 master2 master3 worker1 worker2
do
	sudo virsh define node-configs/ocp4-$i.xml
done

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

dnf install qemu-img jq git httpd squid dhcp-server tftp-server syslinux-tftpboot xinetd net-tools nano bind bind-utils haproxy wget syslinux -y
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
systemctl enable xinetd
systemctl enable tftp
systemctl enable haproxy
systemctl enable rpcbind
systemctl enable nfs-server
mkdir -p /var/lib/tftpboot/pxelinux/pxelinux.cfg/
cp -f /tftpboot/pxelinux.0 /var/lib/tftpboot/pxelinux
cp -f /tftpboot/ldlinux.c32 /var/lib/tftpboot/pxelinux
cp -f /tftpboot/vesamenu.c32 /var/lib/tftpboot/pxelinux
sed -i 's/Listen 80/Listen 81/g' /etc/httpd/conf/httpd.conf
wget $RHCOS_RAW
wget $RHCOS_KERNEL
wget $RHCOS_RAMDISK
wget $OCP_INSTALL
wget $OC_CLIENT
mv rhcos* /var/www/html
mv /var/www/html/*raw* /var/www/html/rhcos.raw.gz
mv /var/www/html/*kernel* /var/www/html/rhcos.kernel
mv /var/www/html/*initramfs* /var/www/html/rhcos.initramfs
chmod -R 777 /var/www/html
restorecon -Rv /var/www/html
tar -zxvf openshift-client*
tar -zxvf openshift-install*
cp oc kubectl /usr/bin/
rm -f oc kubectl
chmod a+x /usr/bin/oc
chmod a+x /usr/bin/kubectl
mkdir -p /root/ocp-install/
echo -e "search cnv.example.com\nnameserver 192.168.123.100" > /etc/resolv.conf
growpart /dev/vda 1
xfs_growfs /
EOF

echo -e "\n\n[INFO] Running the bastion deployment script remotely...\n"

scp -o StrictHostKeyChecking=no bastion-deploy.sh root@192.168.123.100:/root/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 sh /root/bastion-deploy.sh
ssh -o StrictHostKeyChecking=no root@192.168.123.100 rm -f /root/bastion-deploy.sh

echo -e "\n\n[INFO] Configuring the supporting services (squid, haproxy, DNS, DHCP, TFTP, httpd)...\n"

echo -e "\n\n[INFO] Copying the RHEL8 KVM Image into the guest...\n"
scp -o StrictHostKeyChecking=no /var/lib/libvirt/images/rhel8-kvm.qcow2 root@192.168.123.100:/var/www/html/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "qemu-img convert -f qcow2 -O raw /var/www/html/rhel8-kvm.qcow2 /var/www/html/rhel8-kvm.img"

scp -o StrictHostKeyChecking=no configs/dhcpd.conf root@192.168.123.100:/etc/dhcp/dhcpd.conf
scp -o StrictHostKeyChecking=no configs/squid.conf root@192.168.123.100:/etc/squid/squid.conf
scp -o StrictHostKeyChecking=no configs/named.conf root@192.168.123.100:/etc/named.conf
scp -o StrictHostKeyChecking=no configs/haproxy.cfg root@192.168.123.100:/etc/haproxy/haproxy.cfg
scp -o StrictHostKeyChecking=no configs/123.168.192.db root@192.168.123.100:/var/named/123.168.192.db
scp -o StrictHostKeyChecking=no configs/cnv.example.com.db root@192.168.123.100:/var/named/cnv.example.com.db
scp -o StrictHostKeyChecking=no -r pxeboot/* root@192.168.123.100:/var/lib/tftpboot/pxelinux/pxelinux.cfg/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "restorecon -Rv /var/lib/tftpboot/ && chmod -R 777 /var/lib/tftpboot/pxelinux"

cp -f configs/install-config.yaml pre-install-config.yaml
sed -i "s/PULL_SECRET/$PULL_SECRET/g" pre-install-config.yaml
scp -o StrictHostKeyChecking=no pre-install-config.yaml root@192.168.123.100:/root/install-config.yaml
ssh -o StrictHostKeyChecking=no root@192.168.123.100 'sed -i "s|BAST_SSHKEY|$(cat /root/.ssh/id_rsa.pub)|g" install-config.yaml'
ssh -o StrictHostKeyChecking=no root@192.168.123.100 cp /root/install-config.yaml /root/ocp-install/install-config.yaml

ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install/ create manifests"
scp -o StrictHostKeyChecking=no configs/ocp/99* root@192.168.123.100:/root/ocp-install/openshift/
ssh -o StrictHostKeyChecking=no root@192.168.123.100 cp /root/install-config.yaml /root/ocp-install/install-config.yaml

ssh -o StrictHostKeyChecking=no root@192.168.123.100 "./openshift-install --dir=/root/ocp-install/ create ignition-configs"
ssh -o StrictHostKeyChecking=no root@192.168.123.100 "cp /root/ocp-install/*.ign /var/www/html/ && restorecon -Rv /var/www/html && chmod -R 777 /var/www/html"

echo -e "\n\n[INFO] Rebooting bastion host...\n"

ssh -o StrictHostKeyChecking=no root@192.168.123.100 reboot

echo -ne "\n[INFO] Waiting for the ssh daemon on the bastion host to appear"
while [ ! "`nmap -sV -p 22 192.168.123.100|grep open`" ]; do
  echo -n "."
  sleep 1s
done
echo

mkdir -p generated/
mv bastion-deploy.sh pre-install-config.yaml generated/

echo -e "\n\n[INFO] Booting OpenShift nodes (they'll PXE boot automatically)...\n"

sleep 1m

for i in bootstrap master1 master2 master3 worker1 worker2
do
  	sudo virsh start ocp4-$i
done
sleep 20

echo -e "\n\n[INFO] Waiting for OpenShift installation to complete...\n"

ssh -o StrictHostKeyChecking=no root@192.168.123.100 'echo -e "search cnv.example.com\nnameserver 192.168.123.100" > /etc/resolv.conf && chattr +i /etc/resolv.conf'
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

echo -e "\n\n[INFO] Enabling the Image Registry on NFS...\n"

#ssh -o StrictHostKeyChecking=no root@192.168.123.100 "export KUBECONFIG=ocp-install/auth/kubeconfig && oc get configs.imageregistry/cluster -o yaml | sed 's/managementState: Removed/managementState: Managed/g' | oc replace -f -"
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
