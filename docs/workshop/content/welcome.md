[**<u>Work in Progress</u>**]

Welcome to the OpenShift virtualisation self-paced lab guide/workbook. We've put this together to give you an overview and technical deep dive into how OpenShift virtualisation works, and how it will bring virtualisation capabilities to OpenShift over the next few months.

**OpenShift virtualisation** is now the official *product name* for the Container-native virtualisation operator for OpenShift. This has more commonly been referred to as "**CNV**" and is the downstream offering for the upstream [Kubevirt project](https://kubevirt.io/). While some aspects of this lab will still have references to "CNV" any reference to "CNV", "Container-native virtualisation" and "OpenShift virtualisation" can be used interchangeably.

In these labs you'll utilise a virtual environment that mimic as close as (feasibly) possible to a real baremetal UPI OpenShift 4.4 deployment to help get you up to speed with the concepts of OpenShift virtualisation. In this hands-on lab you won't need to deploy OpenShift, that'll already be deployed with the built in `install.sh` script, but it's a completely empty cluster, ready to be configured and used with OpenShift virtualisation.


This is the self-hosted lab guide that will run you through the following:

* **Validating the OpenShift deployment**
* **Deploying OpenShift virtualisation**
* **Setting up Storage for OpenShift virtualisation**
* **Setting up Networking for OpenShift virtualisation**
* **Deploying some CentOS8 / RHEL8 / Fedora31 Test Workloads**
* **Performing Live Migrations and Node Maintenance**
* **Utilising network masquerading on pod networking for VM's**
* **Using the OpenShift Web Console extensions for OpenShift virtualisation**
* **Upgrading OpenShift virtualisation via the Operator Lifecycle**

Within the lab you can cut and paste commands directly from the instructions; but also be sure to review all commands carefully both for functionality and syntax!

> **NOTE**: In some browsers and operating systems you may need to use Ctrl-Shift-C / Ctrl-Shift-V to copy/paste!

Please be very aware, this is a work in progress, there may be some bugs/typo's, and we very much welcome feedback on the content, what's missing, what would be good to have, etc. Please feel free to submit PR's or raise GitHub issues, we're glad of the feedback!



When you're ready...

