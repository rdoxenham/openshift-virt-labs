Live Migration is the process of moving an instance from one node in a cluster to another without interruption. This process can be manual or automatic. This depends if the `evictionStrategy` strategy is set to `LiveMigrate` and the underlying node is placed into maintenance. 

Live migration is an administrative function in OpenShift virtualisation. While the action is visible to all users, only admins can initiate a migration. Migration limits and timeouts are managed via the `kubevirt-config` `configmap`. For more details about limits see the [documentation](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.3/html-single/container-native_virtualization/index#cnv-live-migration-limits-ref_cnv-live-migration-limits).

In our lab you should now have only one VM running. You can check that, and view the underlying host it is on, by looking at the virtual machine's instance with the `oc get vmi` command.

> **NOTE**: In OpenShift virtualisation, the "Virtual Machine" object can be thought of as the virtual machine "source" that virtual machine instances are created from. A "Virtual Machine Instance" is the actual running instance of the virtual machine. The instance is the object you work with that contains IP, networking, and workloads, etc. 

~~~bash
$ oc get vmi
NAME               AGE   PHASE     IP                  NODENAME
rhel8-server-nfs   23h   Running   192.168.123.62/24   ocp4-worker1.cnv.example.com
~~~

In this example we can see the `rhel8-server-nfs` instance is on `ocp4-worker1.cnv.example.com`. As you may recall we deployed this instance with the `LiveMigrate` `evictionStrategy` strategy but you can also review an instance with `oc describe` to ensure it is enabled.

~~~bash
$ oc describe vmi rhel8-server-nfs | egrep -i '(eviction|migration)'
  Eviction Strategy:  LiveMigrate
  Migration Method:  LiveMigration
~~~

The easiest way to initiate a migration is to create an `VirtualMachineInstanceMigration` object in the cluster directly against the `vmi` we want to migrate. But wait! Once we create this object it will trigger the migration, so first, let's review what it looks like and set up our tools to watch the process:

~~~
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstanceMigration
metadata:
  name: migration-job
spec:
  vmiName: rhel8-server-nfs
~~~

It's really quite simple, we create a `VirtualMachineInstanceMigration` object and reference the `LiveMigratable ` instance we want to migrate: `rhel8-server-nfs`. In the lower terminal start a watch command for the migration job; it will come back with an `Error` until you launch the job:

~~~bash
$ watch -n1 oc get virtualmachineinstancemigration/migration-job -o yaml
~~~

In the top terminal let's launch the migration:

~~~bash
$ cat << EOF | oc apply -f -
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstanceMigration
metadata:
  name: migration-job
spec:
  vmiName: rhel8-server-nfs
EOF

virtualmachineinstancemigration.kubevirt.io/migration-job created
~~~

In your watch you should see the job's phases change to reflect the progress. First it will show `phase: Scheduling` 

~~~bash
Every 1.0s: oc get virtualmachineinstancemigration/migration-job -o yaml                 Fri Mar 20 00:33:35 2020

apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstanceMigration
(...)
spec:
  vmiName: rhel8-server-nfs
status:
  phase: Scheduling                                  <-----------
~~~

And then move to `phase: TargetReady` and onto`phase: Succeeded`:

~~~bash
Every 1.0s: oc get virtualmachineinstancemigration/migration-job -o yaml                 Fri Mar 20 00:33:43 2020

apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstanceMigration
(...)
spec:
  vmiName: rhel8-server-nfs
status:
  phase: Succeeded                                  <-----------
~~~

Finally view the `vmi` object and you can see the new underlying host (was *ocp4-worker1*, now it's *ocp4-worker2*); your environment may be the other way around, depending on where `rhel8-server-nfs` was initially scheduled.

~~~bash
$ oc get vmi
NAME               AGE   PHASE     IP                  NODENAME
rhel8-server-nfs   24h   Running   192.168.123.62/24   ocp4-worker2.cnv.example.com
~~~

As you can see Live Migration in OpenShift virtualisation is quite easy. If you have time try some other exmaples. Perhaps start a ping and migrate the machine back. Do you see anything in the ping to indicate the process?

> **NOTE**: If you try and run the same migration job it will report `unchanged`. To run a new job, run the same example as above, but change the job name in the metadata section to something like `name: migration-job2`

Also, rerun the `oc describe vmi rhel8-server-nfs` after running a few migrations. You'll see the object is updated with details of the migrations:

~~~bash
$ oc describe vmi rhel8-server-nfs
(...)
  Migration State:
    Completed:        true
    End Timestamp:    2020-03-20T00:49:08Z
    Migration UID:    43f5b34d-94b4-4cda-9a69-cca8d4b4c587
    Source Node:      ocp4-worker2.cnv.example.com
    Start Timestamp:  2020-03-20T00:49:04Z
    Target Direct Migration Node Ports:
      39037:                      0
      42063:                      49152
    Target Node:                  ocp4-worker1.cnv.example.com
    Target Node Address:          10.131.0.3
    Target Node Domain Detected:  true
    Target Pod:                   virt-launcher-rhel8-server-nfs-hls48
  Node Name:                      ocp4-worker1.cnv.example.com
  Phase:                          Running
  Qos Class:                      Burstable
Events:
  Type    Reason           Age                  From                                        Message
  ----    ------           ----                 ----                                        -------
  Normal  PreparingTarget  16m                  virt-handler, ocp4-worker1.cnv.example.com  Migration Target is l
istening at 10.131.0.3, on ports: 40787,41185
  Normal  Deleted          16m                  virt-handler, ocp4-worker2.cnv.example.com  Signaled Deletion
  Normal  Migrating        16m (x3 over 16m)    virt-handler, ocp4-worker2.cnv.example.com  VirtualMachineInstanc
e is migrating.
  Normal  Migrated         16m (x2 over 16m)    virt-handler, ocp4-worker2.cnv.example.com  The VirtualMachineIns
tance migrated to node ocp4-worker1.cnv.example.com.
  Normal  Created          10m (x13 over 16m)   virt-handler, ocp4-worker1.cnv.example.com  VirtualMachineInstanc
e defined.
  Normal  PreparingTarget  10m (x2 over 10m)    virt-handler, ocp4-worker2.cnv.example.com  VirtualMachineInstanc
e Migration Target Prepared.
  Normal  PreparingTarget  10m                  virt-handler, ocp4-worker2.cnv.example.com  Migration Target is l
istening at 10.128.2.4, on ports: 37865,37631
  Normal  Created          103s (x53 over 24h)  virt-handler, ocp4-worker2.cnv.example.com  VirtualMachineInstanc
e defined.
  Normal  PreparingTarget  85s (x13 over 16m)   virt-handler, ocp4-worker1.cnv.example.com  VirtualMachineInstanc
e Migration Target Prepared.
  Normal  PreparingTarget  85s                  virt-handler, ocp4-worker1.cnv.example.com  Migration Target is l
istening at 10.131.0.3, on ports: 39037,42063

~~~



## Node Maintenance

Building on-top of live migration, many organisations will need to perform node-maintenance, e.g. for software/hardware updates, or for decommissioning. During the lifecycle of a pod, it's almost a given that this will happen without compromising the workloads, but virtual machines can be somewhat more challenging given their legacy nature. Therefore, OpenShift virtualisation has a node-maintenance feature, which can force a machine to no longer be schedulable and any running workloads will be automatically live migrated off if they have the ability to (e.g. using shared storage) and have an appropriate eviction strategy.

Let's take a look at the current running virtual machines and the nodes we have available:

~~~bash
$ oc get nodes
NAME                           STATUS   ROLES    AGE     VERSION
ocp4-master1.cnv.example.com   Ready    master   6h3m    v1.17.1
ocp4-master2.cnv.example.com   Ready    master   6h3m    v1.17.1
ocp4-master3.cnv.example.com   Ready    master   6h3m    v1.17.1
ocp4-worker1.cnv.example.com   Ready    worker   5h54m   v1.17.1
ocp4-worker2.cnv.example.com   Ready    worker   5h54m   v1.17.1

$ oc get vmi
NAME               AGE     PHASE     IP                  NODENAME
rhel8-server-nfs   3h17m   Running   192.168.123.62/24   ocp4-worker2.cnv.example.com
~~~

So in this environment, we have one virtual machine running on *ocp4-worker2*. Let's take down the node for maintenance and ensure that our workload (VM) stays up and running:

~~~bash
$ cat << EOF | oc apply -f -
apiVersion: kubevirt.io/v1alpha1
kind: NodeMaintenance
metadata:
  name: worker2-maintenance
spec:
  nodeName: ocp4-worker2.cnv.example.com
  reason: "Worker2 Maintenance"
EOF

nodemaintenance.kubevirt.io/worker2-maintenance created
~~~

> **NOTE**: You may need to modify the above command to specify `worker1` if your virtual machine is currently running on the first worker. Also note that you **may** lose your browser based web terminal, and you'll need to wait a few seconds for it to become accessible again. 

Now let's check the status of our environment:

~~~bash
$ oc project default
Now using project "default" on server "https://172.30.0.1:443".

$ oc get nodes
NAME                           STATUS                     ROLES    AGE     VERSION
ocp4-master1.cnv.example.com   Ready                      master   6h7m    v1.17.1
ocp4-master2.cnv.example.com   Ready                      master   6h8m    v1.17.1
ocp4-master3.cnv.example.com   Ready                      master   6h7m    v1.17.1
ocp4-worker1.cnv.example.com   Ready                      worker   5h58m   v1.17.1
ocp4-worker2.cnv.example.com   Ready,SchedulingDisabled   worker   5h58m   v1.17.1

$ oc get vmi
NAME               AGE     PHASE     IP                  NODENAME
rhel8-server-nfs   3h23m   Running   192.168.123.62/24   ocp4-worker1.cnv.example.com
~~~



We can remove the maintenance flag by simply deleting the `NodeMaintenance` object:

~~~bash
$ oc get nodemaintenance
NAME                  AGE
worker2-maintenance   5m16s

$ oc delete nodemaintenance/worker2-maintenance
nodemaintenance.kubevirt.io "worker2-maintenance" deleted

$ oc get nodes/ocp4-worker2.cnv.example.com
NAME                           STATUS   ROLES    AGE    VERSION
ocp4-worker2.cnv.example.com   Ready    worker   6h2m   v1.17.1
~~~

Note the removal of the `SchedulingDisabled` annotation on the 'STATUS' column, also note that just because this node has become active again it doesn't mean that the virtual machine will 'fail back' to it.