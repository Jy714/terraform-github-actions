# terraform-github-actions

Provision an AWS **VPC + EC2 + Application Load Balancer** stack with **Terraform**, and deploy it automatically through a **GitHub Actions** CI/CD pipeline.

> This is a learning project. The goal is to practise writing modular Terraform, managing remote state, and automating `terraform init / validate / plan / apply` with GitHub Actions.
>
> Reference video: [Terraform + GitHub Actions CI/CD (YouTube)](https://www.youtube.com/watch?v=v4MP7fvLw44)

---

## Table of Contents

- [terraform-github-actions](#terraform-github-actions)
  - [Table of Contents](#table-of-contents)
  - [Architecture](#architecture)
  - [Project Structure](#project-structure)
  - [Modules](#modules)
    - [`modules/vpc`](#modulesvpc)
    - [`modules/sg`](#modulessg)
    - [`modules/ec2`](#modulesec2)
    - [`modules/alb`](#modulesalb)
  - [Prerequisites](#prerequisites)
  - [Running Locally](#running-locally)
  - [GitHub Actions CI/CD](#github-actions-cicd)
    - [Trigger](#trigger)
    - [Pipeline steps](#pipeline-steps)
    - [Configure GitHub Secrets](#configure-github-secrets)
    - [Deployment flow](#deployment-flow)
  - [Verifying the Deployment](#verifying-the-deployment)
  - [Cleaning Up](#cleaning-up)
  - [What I Learned](#what-i-learned)
  - [Possible Improvements](#possible-improvements)
  - [References](#references)

---

## Architecture

```
                         Internet
                            │
                   ┌────────▼────────┐
                   │ Internet Gateway│
                   └────────┬────────┘
                            │
┌───────────────────────────┼───────────────────────────────┐
│ VPC 10.0.0.0/16           │                               │
│                  ┌────────▼────────┐                      │
│                  │  Application    │  (port 80, HTTP)     │
│                  │  Load Balancer  │                      │
│                  └───┬─────────┬───┘                      │
│                      │         │                          │
│  ┌───────────────────▼──┐  ┌───▼──────────────────┐       │
│  │ PublicSubnet1        │  │ PublicSubnet2        │       │
│  │ 10.0.1.0/24 (AZ a)   │  │ 10.0.2.0/24 (AZ b)   │       │
│  │  ┌────────────────┐  │  │  ┌────────────────┐  │       │
│  │  │ EC2 WebServer1 │  │  │  │ EC2 WebServer2 │  │       │
│  │  │ Apache (httpd) │  │  │  │ Apache (httpd) │  │       │
│  │  └────────────────┘  │  │  └────────────────┘  │       │
│  └──────────────────────┘  └──────────────────────┘       │
│     Security Group: inbound 80 (HTTP) and 22 (SSH)        │
└───────────────────────────────────────────────────────────┘
```

- **Region**: `ap-southeast-2` (Sydney)
- **Terraform state**: stored in the S3 bucket `terraform-vpc-github-actions` under the key `dev/terraform.tfstate`

Resources created:

| Resource | Count | Notes |
|----------|-------|-------|
| VPC | 1 | CIDR `10.0.0.0/16` |
| Public subnet | 2 | One in each of two availability zones |
| Internet Gateway | 1 | Gives the VPC internet access |
| Route table + associations | 1 + 2 | `0.0.0.0/0` routed to the IGW |
| Security group | 1 | Inbound 80/22, all outbound allowed |
| EC2 instance | 2 | `t3.micro`, Amazon Linux 2; Apache and a status page are installed at boot |
| Application Load Balancer | 1 | Listens on port 80 |
| Target group + attachments | 1 + 2 | Registers both EC2 instances with the ALB |

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions CI/CD pipeline
├── Terraform-VPC/
│   ├── provider.tf             # AWS provider + S3 backend
│   ├── main.tf                 # Root module wiring the child modules together
│   ├── variables.tf            # Root module variables
│   ├── terraform.tfvars        # Variable values (CIDRs, etc.)
│   └── modules/
│       ├── vpc/                # VPC, subnets, IGW, route table
│       ├── sg/                 # Security group
│       ├── ec2/                # EC2 instances + user_data web page
│       └── alb/                # ALB, listener, target group
├── .gitignore
└── README.md
```

---

## Modules

The root module [Terraform-VPC/main.tf](Terraform-VPC/main.tf) calls four child modules in dependency order. Values flow between modules through `output` → input variable:

```
vpc ──(vpc_id)──────────────► sg, alb
vpc ──(subnet_ids)──────────► ec2, alb
sg  ──(sg_id)───────────────► ec2, alb
ec2 ──(instances)───────────► alb
```

### `modules/vpc`
- Creates an `aws_vpc` and uses `count` to create one subnet per entry in `subnet_cidr`.
- Uses `data "aws_availability_zones"` so each subnet lands in a different AZ.
- Outputs: `vpc_id`, `subnet_ids`.

### `modules/sg`
- A single security group allowing HTTP (80) and SSH (22).
- Output: `sg_id`.

### `modules/ec2`
- Looks up the latest Amazon Linux 2 AMI with `data "aws_ami"` instead of hard-coding an AMI ID.
- Creates one instance per name in `ec2_names` (default `WebServer1`, `WebServer2`), each in a different subnet.
- The `user_data` script installs Apache and writes an `index.html` showing the instance ID, type and AZ (read from instance metadata), so you can see the ALB switching between instances.
- Output: `instances` (list of instance IDs).

### `modules/alb`
- Creates an internet-facing Application Load Balancer, an HTTP listener on port 80 and a target group.
- Uses `count = length(var.instances)` to attach every EC2 instance to the target group.

---

## Prerequisites

1. An **AWS account** and an IAM user access key with permissions for VPC, EC2, ELB and S3.
2. An **S3 bucket** for remote state, created manually beforehand. Its name must match `provider.tf`. Bucket names are globally unique, so change it if the name is taken:
   ```bash
   aws s3api create-bucket --bucket terraform-vpc-github-actions --region ap-southeast-2 --create-bucket-configuration LocationConstraint=ap-southeast-2
   ```
3. For local runs:
   - [Terraform](https://developer.hashicorp.com/terraform/install) (the AWS provider is pinned to `~> 6.0`)
   - [AWS CLI](https://aws.amazon.com/cli/) (optional, for configuring credentials)

---

## Running Locally

```bash
cd Terraform-VPC
```

Configure AWS credentials, either with the CLI:

```bash
aws configure
```

or with environment variables:

```bash
export AWS_ACCESS_KEY_ID=xxxx
export AWS_SECRET_ACCESS_KEY=xxxx
```

Then run the standard Terraform workflow:

```bash
terraform init       # Download providers and connect to the S3 backend
terraform fmt        # Format the code
terraform validate   # Check the configuration is valid
terraform plan       # Preview the resources to be created
terraform apply      # Create the resources (type "yes" to confirm)
```

---

## GitHub Actions CI/CD

Workflow file: [.github/workflows/deploy.yml](.github/workflows/deploy.yml)

### Trigger
The pipeline runs on every **push to the `main` branch**. Day-to-day work happens on the `feature` branch, and infrastructure is only deployed once changes are merged into `main`.

### Pipeline steps

| Step | Purpose |
|------|---------|
| Checkout | Check out the repository |
| Set up Terraform | Install Terraform with `hashicorp/setup-terraform` |
| Terraform init | Initialise and connect to the S3 backend |
| Terraform validate | Validate the configuration |
| Terraform plan | Produce an execution plan |
| Terraform apply | Deploy to AWS with `--auto-approve` |

Every Terraform command runs inside the Terraform directory via `working-directory: ./Terraform-VPC`.

### Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name | Value |
|-------------|-------|
| `AWS_ACCESS_KEY` | The IAM user's Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | The IAM user's Secret Access Key |

### Deployment flow

```bash
git checkout feature
# edit the Terraform code ...
git add .
git commit -m "your change"
git push origin feature
# Open a PR from feature -> main on GitHub; merging it triggers the pipeline
```

Logs for each step are available on the repository's **Actions** tab.

---

## Verifying the Deployment

1. In the AWS Console, go to **EC2 → Load Balancers** and copy the **DNS name** of `application-load-balancer`.
2. Open `http://<ALB-DNS-name>` in a browser.
3. The page shows "Your EC2 Instance is running!" with the instance ID, type and availability zone.
4. Refresh a few times: the instance ID and AZ alternate between the two servers, which shows the load balancer is working.

---

## Cleaning Up

Destroy the resources when you're done to avoid charges (the ALB and EC2 instances are billed hourly):

```bash
cd Terraform-VPC
terraform destroy
```

The S3 state bucket is not managed by Terraform. Delete it manually if you no longer need it.

---

## What I Learned

- **Modules**: VPC / SG / EC2 / ALB are split into separate modules, each with its own `variables.tf`, `main.tf` and `outputs.tf`; the root module assembles them.
- **`count` and `count.index`**: one resource block creates multiple subnets, instances and attachments.
- **Data sources**: `aws_ami` and `aws_availability_zones` look values up dynamically instead of hard-coding them.
- **Remote backend**: state lives in S3, so local runs and GitHub Actions share the same state and don't create duplicate resources.
- **`.terraform.lock.hcl`**: locks provider versions and should be committed (the `.gitignore` keeps it).
- **`.gitignore`**: ignores `.terraform/`, `*.tfstate`, `*.pem` and similar files so secrets don't leak.
- **CI/CD**: AWS credentials live in GitHub Secrets and are never hard-coded in the pipeline.

---

## Possible Improvements

- [ ] Enable state locking on the S3 backend (`use_lockfile = true` or DynamoDB).
- [ ] Use **OIDC** (`aws-actions/configure-aws-credentials`) instead of long-lived access keys.
- [ ] Run only `plan` on pull requests and post the result as a PR comment; `apply` only on merge to `main`.
- [ ] Upgrade `actions/checkout` to v4 and `hashicorp/setup-terraform` to v3.
- [ ] Add an `outputs.tf` to the ALB module that exposes the DNS name, and output it from the root module.
- [ ] Restrict SSH (22) to your own IP instead of `0.0.0.0/0`.
- [ ] Move EC2 instances into private subnets and keep only the ALB public.
- [ ] Add a `terraform fmt -check` step to the pipeline.

---

## References

- YouTube tutorial: https://www.youtube.com/watch?v=v4MP7fvLw44
- [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions documentation](https://docs.github.com/actions)
