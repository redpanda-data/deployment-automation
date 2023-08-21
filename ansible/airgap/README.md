## Information for Creating an Airgapped Redpanda Cluster

### What is Airgapping

An airgapped cluster is inaccessible to the wider internet. While a truly airgapped cluster has no physical connection
whatsoever to external networks, in our context it mostly means firewalled from external access.

### Cluster Characteristics

A proxy enables external access through a gateway of some sort. In our proxied cluster the network layout we've chosen
is:

* 1 client per AZ with limited access to the internet on a public subnet with
* 3 brokers and a monitor node on an internal only subnet
* Firewall rules allowing limited traffic between the client and the brokers/monitor
* Squid proxy enabling passthrough traffic
* manual install of Redpanda binaries
* playbooks to download and bundle Redpanda binaries for install

It's important to note that while we fully support a proxied cluster and can deploy one from scratch using our terraform
and ansible modules, it may make sense for you to make changes to the configuration we provide depending on your
security, network and performance needs.

### General Considerations

When building an airgapped or proxied cluster there are a number of considerations to keep in mind:

* You will need a way to prep the nodes such that all dependencies are installed
* You will need a way to provide ssh access to the ansible host if using ansible
* You will need to support HTTP and HTTPS traffic
* You will need to support cert based communication

### Zero external network access

In a scenario where data needs to be fully secure and you cannot even have a proxy between your brokers and the external
internet we recommend:

* using pre-configured AMIs/VMs that have all necessary dependencies
* using Redhat Satellite/Aptly to provide an internal repository for necessary packages to keep everything up to date
* Adding Redpanda's repositories to your Repository Management Tool and installing from there

If you don't have an RMT, it can make sense to take advantage of our binary bundling playbook. This will allow you to
install the binaries directly via a tarball but makes updating more painful
