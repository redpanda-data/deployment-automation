# Redpanda Deployment on IBM Cloud 

This guide and accompanying terraform script is a template that allows for the deployment of infrastructure on IBM Cloud using VPC and VSIs in preparation of running the Redpanda ansible scripts.

## Configuration 

You can update the [variables.tf](./variables.tf) to adjust the number of nodes, region, zone, etc.

## Provisioning 

### 1. Install Terraform on  your machine

```
brew install tfenv
tfenv install 1.0.0
tfenv use 1.0.0
terraform ## should see it all come to life
```

### 2. IBM Cloud Pre-requisites

1. [Get IBM Cloud API Key](https://www.ibm.com/docs/en/app-connect/containers_cd?topic=servers-creating-cloud-api-key)
2. [Set Up SSH key](https://cloud.ibm.com/docs/ssh-keys?topic=ssh-keys-adding-an-ssh-key)
3. Creating COS Instance and Bucket:

    The Terraform configuration's utilizes a Cloud Object Store (COS) object to store the Terraform state. This allows for the same infrastructure to be managed across Terraform instances enabling collaboration between users. Here are the steps followed to configure this feature.

    1. On IBM cloud provision a new COS bucket. This can be done through the IBM Cloud Console with more about that being read [here](https://cloud.ibm.com/docs/cloud-object-storage?topic=cloud-object-storage-getting-started-cloud-object-storage#getting-started)
    2. Create an HMAC service credential for your COS bucket.
        1. Navigate to IBM Cloud console to the Object Store panel
        2. On the side panel navigate to Service Credentials. Note the `cos_hmac_keys` values
    3. Export the environment variables `AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY` 
    ```
    export AWS_ACCESS_KEY_ID=<access_key_id>
    export AWS_SECRET_ACCESS_KEY=<secret_access_key> 
    ```

    Now when you use the Terraform scripts, the Terraform state file will be saved and pulled from your COS bucket instead of locally

### 3. Configure your terraform
 
1. Declare the following environment variables required for Terraform to connect to your IBM Cloud instance:
    - `ibmcloud_api_key` is the ibmcloud API key you generated in step 2 above. Run the following to set the environment variable:
        ``` 
        export TF_VAR_ibmcloud_api_key=<your API key>
        ```
    - `ssh_key` should be the name of your `ssh_key` you created.
        ```
        export TF_VAR_ssh_key=<your API key>
        ```
    - `resource_group` needs the resource group ID not the name. You can get that from using the IBM Cloud CLI: `ibmcloud resource groups` and grab the ID. 
        ```
        export TF_VAR_resource_group=<resource group Id>
        ```

### 4. Run Terraform

Make sure you are logged into the correct account on IBM Cloud and have correct IAM entitlements to provision infrastructure in a VPC. 

- Initialize Environment `terraform init`
- Check the plan `terraform plan`
- Apply the plan `terraform apply`

### 5. Setting Up VMs

After the above steps, you should have root access tied to the `ssh_key` that was specified. This means that you can log in to the boxes using `ssh root@<public ip>`. 

However, if you would like to create a a separte user for someone else that will install redpanda. Here are the steps. 

1. Log into the box: `ssh root@<public ip>`.
2. Create dev user: `adduser dev`
3. Give dev user sudo access: `usermod -aG sudo dev`
4. Permit users to access dev from local, by adding public key to `.ssh/authorized_users`
    1. switch user: `su - dev`
    2. make directory: `mkdir .ssh && cd .ssh`
    3. Run `echo [insert your public key from your .ssh/id_rsa.pub] >> authorized_keys`

# References

https://cloud.ibm.com/docs/ibm-cloud-provider-for-terraform?topic=ibm-cloud-provider-for-terraform-sample_vpc_config