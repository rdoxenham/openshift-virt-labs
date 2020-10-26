#!/usr/bin/env bash

echo -e "[INFO] Make sure that you've installed the local-storage and OpenShift Container Storage operators first! (10s sleep..)"
sleep 10

export KUBECONFIG=~/ocp-install/auth/kubeconfig

echo -e "\n[INFO] Labelling the workers as OCS capable nodes..."
for i in 1 2 3; do
	oc label nodes ocp4-worker$i.cnv.example.com cluster.ocs.openshift.io/openshift-storage=''
done

echo -e "\n[INFO] Deploying the LocalVolume CR to point to available block devices..."
cat << EOF | oc apply -f -
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-block
  namespace: local-storage
  labels:
    app: ocs-storagecluster
spec:
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: cluster.ocs.openshift.io/openshift-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: localblock
      volumeMode: Block
      devicePaths:
        - /dev/vdb
        - /dev/vdc
EOF

echo -e "\n[INFO] Sleeping whilst local volumes get scanned and PV's are created... (60s)"
sleep 5
echo ""
oc get sc
sleep 15
echo ""
oc get pods -n local-storage
sleep 40

echo -e "\n[INFO] Printing PV's (make sure you see 6 local-storage volumes...)"
oc get pv
sleep 5

echo -e "\n[INFO] Deploying the OCS Storage cluster to use these volumes..."
cat << EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  monDataDirHostPath: /var/lib/rook
  storageDeviceSets:
  - count: 2
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: localblock
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 3
    resources: {}
EOF

echo -e "\n[INFO] Getting latest storage classes to validate Ceph availability...\n"
sleep 5
oc get sc

echo -e "\n[INFO] Patching configuration to deploy the toolbox..."
oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
