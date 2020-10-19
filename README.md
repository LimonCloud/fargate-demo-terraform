# AWS Fargate Terraform Demo

## Prerequisites

1- You need to have terraform installed and be callable from the CLI.

2- If you want the demo to work on your account, you must request an SSL certificate from the Certificate Manager, on which region you would like to deploy.

3- Then set all this information on variables.tf, as well as with existing VPC ID and Public Subnet IDs.

4- Next, you need to create an Elastic Container Registry (ECR) repository on which region you would like to deploy, and use this repository link inside the main.
tf on line: 235 and also in the buildspec.yml file in the source code.

5- The last thing to change is, create a CloudWatch Log Group on the region you are on, and change line 248 on main.tf, accordingly.

6- Don't forget to double check region variables on both terraform, and buildspec.yml in the source.

7- You are now ready to:

--
```
$ terraform init
$ terraform plan
$ terraform apply
```

Good luck and feel free to ask us for a giving hand!