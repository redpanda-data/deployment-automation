# Redpanda on EKS

Amazon Elastic Kubernetes Service (EKS) enables us to run the Redpanda Kubernetes cluster in the AWS cloud. It manages the control plane for us, so we can concentrate on what the worker nodes are doing.

### Accessing the Redpanda EKS dev cluster

**Prerequisites**

1. [Install `kubectl`.](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

2. [Install `helm`.](https://helm.sh/docs/intro/install/)

3. [Install the `aws` command-line.](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

   You will need this in your `.bash_profile` or equivalent shell initialization file (put in the keys that were given to you when your AWS was set up):

   ```
   export AWS_ACCESS_KEY_ID=<My_Access_Key_Id>
   export AWS_SECRET_ACCESS_KEY=<My_Secret_Access_Key>
   ```

4. Check that you have Vectorized AWS access. This command should return your AWS identity:
   
   ``` 
   $ aws sts get-caller-identity 
   ```

   You should also be able to see the `redpanda-dev1` cluster in the AWS Console:
   https://us-east-2.console.aws.amazon.com/eks/home?region=us-east-2#/clusters/redpanda-dev1

   You may need to change the region and/or cluster name in the URL. Check with the cluster creator, or create your own cluster -- see Admin functions below.
   
5. [Install `eksctl`.](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html#install-eksctl)

6. Ensure you have a local copy of the [`deployment-automation` repository](https://github.com/vectorizedio/deployment-automation).

7. Because Kubernetes has its own authorization system (RBAC), your IAM account in AWS will need to be made known to the EKS Redpanda cluster. This is currently done by a cluster admin putting your IAM details in a file [`aws-auth-redpanda.yaml`](https://github.com/vectorizedio/deployment-automation/kubernetes/eks/aws-auth-redpanda.yaml) (a ConfigMap) and calling: 

   ```
   kubectl apply -f aws-auth-redpanda.yaml
   ```

**Steps**

1. Update your `~/.kube/config` using the AWS CLI. This allows `kubectl` to access the remote `redpanda-dev1` cluster.

   ```
   $ aws eks update-kubeconfig --name redpanda-dev1 --region us-east-2
   ```

2. Check that you can see the remote Kubernetes service:

   ```
   $ kubectl get svc
   NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
   kubernetes   ClusterIP   10.100.0.1   <none>        443/TCP   3h20m
   
   $ kubectl cluster-info
   Kubernetes master is running at https://5C4D7609E7F8AFF641ECF35227AF3160.gr7.us-east-2.eks.amazonaws.com
   CoreDNS is running at https://5C4D7609E7F8AFF641ECF35227AF3160.gr7.us-east-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
   ```

3. In the AWS Management Console go to Workloads for the cluster to see if the Redpanda Helm Chart is already installed.  If not, you can install it. In your terminal, go to the `deployment-automation/kubernetes` folder and run:

   ```
   $ helm install --namespace redpanda --create-namespace redpanda ./redpanda
   ```

   This will output instructions on how to run `rpk` on the EKS cluster, for example:

   ```
   $ kubectl -n redpanda run -ti --rm --restart=Never --image vectorized/redpanda rpk -- --brokers=redpanda:9092 api topic create topic1 --partitions=3 --replicas=3
   
   $ kubectl -n redpanda run -ti --rm --restart=Never --image vectorized/redpanda rpk -- --brokers=redpanda:9092 api status 
   ```

   It things are not working as expected, you can also uninstall the Helm Chart and then install again. The uninstall command is:

   ```
   $ helm -n redpanda uninstall redpanda
   ```

**Admin functions**

The `redpanda-dev1.yaml` file in this folder contains settings and provisioning for the Redpanda EKS cluster used by `eksctl`.

- To delete the cluster (use the correct region), call:
  
  ```
  $ eksctl delete cluster --region us-east-2 --name redpanda-dev1
  ```

  (You can use the AWS Management Console to make sure no resources were left behind. For example, if you look at the [**CloudFormation**](https://us-east-2.console.aws.amazon.com/cloudformation/home?region=us-east-2) page, you will see it takes a few seconds to clean up the nodes. Also it is good to look at [all instances](https://us-east-2.console.aws.amazon.com/ec2/v2/home?region=us-east-2#Instances:) from time to time to check that none have accidentally been left running.)

- To recreate the cluster, copy the `.ssh/vectorized-ec2.pub` from this folder to your `~/.ssh`, and call:

  ```
  $ eksctl create cluster -f redpanda-dev1.yaml
  ```

  This takes a few minutes.

- The node group for the cluster is added independently:

   ```
   $ eksctl create nodegroup --config-file=redpanda-dev1-nodegroup.yaml
   ```

   This also takes a few minutes.

- To let other developers access the cluster, ensure their IAM account is in the `aws-auth-redpanda.yaml` file in this folder. This ConfigMap also authorizes nodes, so first ensure that the right `NodeInstanceRole`is in there. To see the current auth-map for the cluster, call

   ```
   kubectl edit -n kube-system configmap/aws-auth
   ```

   Copy the `mapRoles` section. Exit the editor, then paste that into your local copy of `aws-auth-redpanda.yaml`, overwriting the existing `mapRoles` section.

   Then call:

   ```
   $ kubectl apply -f aws-auth-redpanda.yaml
   ```

   This should preserve the `NodeInstanceRole`, while authorizing users.

**Tips**

- You might find it useful to download [Lens](https://github.com/lensapp/lens), a tool for visualizing Kubernetes clusters.

**Troubleshooting**

- If you run `kubectl`commands and they show no information about Redpanda, make sure they use the correct namespace by including `-n redpanda`.
- If you run `eksctl` commands and they show no information about the cluster, make sure they point to the right Amazon region by including (e.g.) `--region us-east-2`.

