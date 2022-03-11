## Installation

## Local Machine Set up 

```
brew install tfenv
tfenv install 1.0.0
tfenv use 1.0.0
terraform ## should see it all come to life
```

## Configure COS Bucket
The Terraform configuration's utilizes a Cloud Object Store (COS) object to store the Terraform state. This allows for the same infrastructure to be managed across Terraform instances enabling collaboration between users. Here are the steps followed to configure this feature.

1. On IBM cloud provision a new COS bucket. This can be done through the IBM Cloud Console with more about that being read [here](https://cloud.ibm.com/docs/cloud-object-storage?topic=cloud-object-storage-getting-started-cloud-object-storage#getting-started)
2. Create an HMAC service credential for your COS bucket.
   1. Navigate to IBM Cloud console to the Object Store panel
   2. On the side panel navigate to Service Credentials. Note the `cos_hmac_keys` values
3. Export the environment variables `AWS_ACCESS_KEY_ID=<access_key_id>` and `AWS_SECRET_ACCESS_KEY=<secret_access_key>` 

Now when you use the Terraform scripts, the Terraform state file will be saved and pulled from your COS bucket instead of locally

If you rather not use a COS bucket and only locally store the Terraform state, comment out lines 2-10 in (versions.tf)[./versions.tf] to disable the COS bucket backend.

## Running this
Make sure you are logged into the correct account on IBM Cloud and have correct VPC permissions with a registered SSH key on your Cloud Account. . 

- Initialize Environment`terraform init`
- Check the plan `terraform plan`
- Apply the plan `terraform apply`

### Setting Up VMs
- Create dev user: `adduser dev`
- Give dev user sudo access: `usermod -aG sudo dev`
- Permit users to access dev from local, by adding public key to `.ssh/authorized_users`
    - switch user: `su - dev`
    - make directory: `mkdir .ssh && cd .ssh`
    - Run `echo [insert your public key from your .ssh/id_rsa.pub] >> authorized_keys`

#### Installing Java (for confluent kafka)
https://www.digitalocean.com/community/tutorials/how-to-install-java-with-apt-on-ubuntu-20-04

Go to each zookper and kafka node: 
```
apt-get update
apt install default-jre
```

### References

https://cloud.ibm.com/docs/ibm-cloud-provider-for-terraform?topic=ibm-cloud-provider-for-terraform-sample_vpc_config