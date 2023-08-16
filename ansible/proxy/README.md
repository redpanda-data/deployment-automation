## Information for Creating a Proxied Redpanda Cluster

## What is Proxying

In our context a proxied cluster is firewalled from all external access except through a proxy (in our case Squid). All
traffic must pass through the proxy before it can access the cluster

## Cluster Characteristics

A proxy enables external access through a gateway of some sort. In our proxied cluster the network layout we've chosen
is:

* 1 client per AZ with limited access to the internet on a public subnet with
* 3 brokers and a monitor node on an internal only subnet
* Firewall rules allowing limited traffic between the client and the brokers/monitor
* Squid proxy enabling passthrough traffic

It's important to note that while we fully support a proxied cluster and can deploy one from scratch using our terraform
and ansible modules, it may make sense for you to make changes to the configuration we provide depending on your
security, network and performance needs.

### General Considerations

When building an airgapped or proxied cluster there are a number of considerations to keep in mind:

* You will need a way to prep the nodes such that all dependencies are installed
* You will need a way to provide ssh access to the ansible host if using ansible
* You will need to support HTTP and HTTPS traffic
* You will need to support cert based communication
