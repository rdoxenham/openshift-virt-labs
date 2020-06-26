In this section we're going to be configuring the networking for our environment. 

With OpenShift virtualisation we have a few different options for networking - we can just have our virtual machines be attached to the same pod networks that our containers would have access to, or we can configure more real-world virtualisation networking constructs like bridged networking, SR/IOV, and so on. It's also absolutely possible to have a combination of these, e.g. both pod networking and a bridged interface directly attached to a VM at the same time, using Multus, the default networking CNI in OpenShift 4.x.

In this lab we're going to enable multiple options - pod networking and a secondary network interface provided by a bridge on the underlying worker nodes (hypervisors). Each of the worker nodes has been configured with an additional, currently unused, network interface that is defined as `enp2s0`, and we'll need a bridge device, `br1` to be created so we can attach our virtual machines to it. The first step is to use the new Kubernetes NetworkManager state configuration to setup the underlying hosts to our liking. Recall that we can get the **current** state by requesting the `NetworkNodeState`:


~~~bash
$ oc get nns/ocp4-worker1.cnv.example.com -o yaml
apiVersion: nmstate.io/v1alpha1
kind: NodeNetworkState
metadata:
  creationTimestamp: "2020-03-16T12:57:34Z"
  generation: 1
  name: ocp4-worker1.cnv.example.com
  ownerReferences:
  - apiVersion: v1
    kind: Node
    name: ocp4-worker1.cnv.example.com
    uid: 3263293d-34bc-4299-92bf-3b7b3ac37fd2
  resourceVersion: "764272"
  selfLink: /apis/nmstate.io/v1alpha1/nodenetworkstates/ocp4-worker1.cnv.example.com
  uid: 470042d7-24fa-4be4-bdf2-70addaf3e876
status:
  currentState:
    dns-resolver:
      config:
        search: []
        server: []
      running:
        search:
        - cnv.example.com
        - cnv.example.com
        server:
        - 192.168.123.100
        - 192.168.123.100
    interfaces:
    - ipv4:
        enabled: false
      ipv6:
        enabled: false
      mtu: 1450
      name: br0
      state: down
      type: ovs-interface
    - ipv4:
        address:
        - ip: 192.168.123.104
          prefix-length: 24
        auto-dns: true
        auto-gateway: true
        auto-routes: true
        dhcp: true
        enabled: true(...)
~~~

In there you'll spot the interface that we'd like to use to create a bridge, `enp2s0`, ignore the IP address that it has right now, that just came from the DHCP host on the bastion machine, but it's not currently being used:

~~~bash
    - ipv4:
        address:
        - ip: 192.168.123.63
          prefix-length: 24
        auto-dns: true
        auto-gateway: true
        auto-routes: true
        dhcp: true
        enabled: true
      ipv6:
        address:
        - ip: fe80::fba3:fadc:30c1:6361
          prefix-length: 64
        auto-dns: true
        auto-gateway: true
        auto-routes: true
        autoconf: true
        dhcp: true
        enabled: true
      mac-address: 52:54:00:47:5E:94
      mtu: 1500
      name: enp2s0
      state: up
      type: ethernet
~~~

> **NOTE**: The first interface `enp1s0` via `br0` is being used for inter-OpenShift communication, including all of the pod networking via OpenShift SDN.


Now we can apply a new `NodeNetworkConfigurationPolicy` for our worker nodes to setup a desired state for `br1` via `enp2s0`, noting that in the `spec` we specify a `nodeSelector` to ensure that this **only** gets applied to our worker nodes:

~~~bash
$ cat << EOF | oc apply -f -
apiVersion: nmstate.io/v1alpha1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: br1-enp2s0-policy-workers
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  desiredState:
    interfaces:
      - name: br1
        description: Linux bridge with enp2s0 as a port
        type: linux-bridge
        state: up
        ipv4:
          enabled: false
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: enp2s0
EOF

nodenetworkconfigurationpolicy.nmstate.io/br1-enp2s0-policy-workers created
~~~

Then enquire as to whether it was successfully applied:

~~~bash
$ oc get nncp
NAME                        STATUS
br1-enp2s0-policy-workers   SuccessfullyConfigured

$ oc get nnce
NAME                                                     STATUS
ocp4-master1.cnv.example.com.br1-enp2s0-policy-workers   NodeSelectorNotMatching
ocp4-master2.cnv.example.com.br1-enp2s0-policy-workers   NodeSelectorNotMatching
ocp4-master3.cnv.example.com.br1-enp2s0-policy-workers   NodeSelectorNotMatching
ocp4-worker1.cnv.example.com.br1-enp2s0-policy-workers   SuccessfullyConfigured
ocp4-worker2.cnv.example.com.br1-enp2s0-policy-workers   SuccessfullyConfigured
~~~

We can also dive into the `NetworkNodeConfigurationPolicy` (**nncp**) a little further:

~~~bash
$ oc get nncp/br1-enp2s0-policy-workers -o yaml
apiVersion: nmstate.io/v1alpha1
kind: NodeNetworkConfigurationPolicy
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"nmstate.io/v1alpha1","kind":"NodeNetworkConfigurationPolicy","metadata":{"annotations":{},"name":"br1-enp
2s0-policy-workers"},"spec":{"desiredState":{"interfaces":[{"bridge":{"options":{"stp":{"enabled":false}},"port":[{"name":"enp
2s0"}]},"description":"Linux bridge with enp2s0 as a port","ipv4":{"enabled":false},"name":"br1","state":"up","type":"linux-br
idge"}]},"nodeSelector":{"node-role.kubernetes.io/worker":""}}}
  creationTimestamp: "2020-03-17T01:55:53Z"
  generation: 1
  name: br1-enp2s0-policy-workers
  resourceVersion: "329509"
  selfLink: /apis/nmstate.io/v1alpha1/nodenetworkconfigurationpolicies/br1-enp2s0-policy-workers
  uid: 8335c461-5864-48c8-bb86-d6c6e71ae4c4
spec:
  desiredState:
    interfaces:
    - bridge:
        options:
          stp:
            enabled: false
        port:
        - name: enp2s0
      description: Linux bridge with enp2s0 as a port
      ipv4:
        enabled: false
      name: br1
      state: up
      type: linux-bridge
  nodeSelector:
    node-role.kubernetes.io/worker: ""
status:
  conditions:
  - lastHearbeatTime: "2020-03-17T01:56:00Z"
    lastTransitionTime: "2020-03-17T01:56:00Z"
    reason: SuccessfullyConfigured
    status: "False"
    type: Degraded
  - lastHearbeatTime: "2020-03-17T01:56:00Z"
    lastTransitionTime: "2020-03-17T01:56:00Z"
    message: 2/2 nodes successfully configured
    reason: SuccessfullyConfigured
    status: "True"
    type: Available
~~~


Now that the "physical" networking is configured on the underlying worker nodes, we need to then define a `NetworkAttachmentDefinition` so that when we want to use this bridge, OpenShift and OpenShift virtualisation know how to attach into it. This associates the bridge we just defined with a logical name, known here as '**tuning-bridge-fixed**':

~~~bash
$ cat << EOF | oc apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: tuning-bridge-fixed
  annotations:
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/br1
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "groot",
    "plugins": [
      {
        "type": "cnv-bridge",
        "bridge": "br1"
      },
      {
        "type": "tuning"
      }
    ]
  }'
EOF

networkattachmentdefinition.k8s.cni.cncf.io/tuning-bridge-fixed created
~~~

> **NOTE**: The important flags to recognise here are the **type**, being **cnv-bridge** which is a specific implementation that links in-VM interfaces to a counterpart on the underlying host for full-passthrough of networking. Also note that there is no **ipam** listed - we don't want the CNI to manage the network address allocation for us - the network we want to attach to has DHCP enabled, and so let's not get involved.