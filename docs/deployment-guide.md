
# AWS High Availability Web Application — Deployment Guide

## Overview

This guide documents the manual deployment of a highly available web application infrastructure in AWS using the AWS Management Console and AWS CLI.

**Region:** eu-north-1 (Stockholm)

**Deployment method:** AWS Console and AWS CLI

**Application:** Python HTTP server running on TCP port 8002

**Load balancing:** Internet-facing Network Load Balancer

**Scaling:** EC2 Auto Scaling Group with 50% CPU target tracking

**Database:** PostgreSQL 16 on two independent EC2 instances in private subnets

## Infrastructure Components

- Custom VPC with CIDR 10.0.0.0/16
- Two public and two private subnets across two Availability Zones
- Internet Gateway
- Public NAT Gateway
- Bastion Host
- EC2 Launch Template
- EC2 Auto Scaling Group
- Network Load Balancer and Target Group
- Two private PostgreSQL instances
- AWS Security Groups
- Amazon CloudWatch dashboards and alarms

## Deployment Sequence


## 1. Create the VPC and Subnets

### Step 1 — Create the VPC

Open **AWS Console → VPC → Your VPCs → Create VPC**.

Configure:

- Name: `HA-WebApp-VPC`
- IPv4 CIDR: `10.0.0.0/16`
- Region: `eu-north-1`
- Tenancy: Default

### Step 2 — Create the Subnets

Navigate to **VPC → Subnets → Create subnet**.

Create four subnets:

| Subnet | CIDR | Availability Zone | Type |
|---|---|---|---|
| HA-Public-1a | 10.0.1.0/24 | eu-north-1a | Public |
| HA-Public-2b | 10.0.2.0/24 | eu-north-1b | Public |
| HA-Private-1a | 10.0.11.0/24 | eu-north-1a | Private |
| HA-Private-2b | 10.0.12.0/24 | eu-north-1b | Private |

### Step 3 — Configure Public IPv4 Assignment

For both public subnets:

1. Select the subnet.
2. Choose **Actions → Edit subnet settings**.
3. Enable **Auto-assign public IPv4 address**.
4. Save changes.

For both private subnets, leave automatic public IPv4 assignment disabled.

**Important:** A subnet becomes public when its effective route table contains a route to an Internet Gateway. Automatic public IP assignment alone does not make a subnet public.

### Step 4 — Verify the Subnets Using AWS CLI

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=HA-Public-1a,HA-Public-2b,HA-Private-1a,HA-Private-2b" \
  --region eu-north-1 \
  --query "Subnets[*].[Tags[?Key=='Name']|[0].Value,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]" \
  --output table
```

Expected:

- Four subnets in the same VPC.
- Two subnets in `eu-north-1a`.
- Two subnets in `eu-north-1b`.
- Public IPv4 assignment enabled only for public subnets.

## 2. Configure Internet Gateway, NAT Gateway, and Route Tables

### Step 1 — Create and Attach an Internet Gateway

Navigate to **AWS Console → VPC → Internet Gateways → Create internet gateway**.

Configure:

- Name: `HA-WebApp-IGW`
- VPC: `HA-WebApp-VPC`

After creating the Internet Gateway, select **Actions → Attach to VPC** and attach it to `HA-WebApp-VPC`.

The Internet Gateway provides internet connectivity for resources in public subnets when appropriate routes and security settings are configured.

### Step 2 — Create the Public Route Table

Navigate to **VPC → Route Tables → Create route table**.

Configure:

- Name: `HA-Public-RT`
- VPC: `HA-WebApp-VPC`

Add the following routes:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | Local |
| `0.0.0.0/0` | Internet Gateway (`HA-WebApp-IGW`) |

Under **Subnet associations**, associate:

- `HA-Public-1a`
- `HA-Public-2b`

### Step 3 — Create a Public NAT Gateway

Navigate to **VPC → NAT Gateways → Create NAT gateway**.

Configure:

- Name: `HA-WebApp-NAT`
- Subnet: `HA-Public-1a`
- Connectivity type: Public
- Elastic IP: Allocate and associate an Elastic IP address

The NAT Gateway provides outbound IPv4 connectivity for EC2 instances in private subnets without allowing unsolicited inbound internet connections through the gateway.

**Note:** This lab uses one NAT Gateway in `eu-north-1a` for both private subnets. For production-level availability, consider

## 3. Configure AWS Security Groups

Security Groups act as stateful virtual firewalls that control inbound and outbound network traffic for AWS resources.

This project uses four dedicated Security Groups to separate public access, application traffic, administrative access, and database connectivity.

### Step 1 — Create the Bastion Host Security Group

Navigate to **EC2 → Security Groups → Create security group**.

Configure:

- Name: `HA-Bastion-SG`
- VPC: `HA-WebApp-VPC`
- Description: Restrict SSH access to the Bastion Host

**Inbound rule:**

| Type | Protocol | Port | Source |
|---|---|---|---|
| SSH | TCP | 22 | Administrator's public IP `/32` |

Do not permit SSH from `0.0.0.0/0`.

### Step 2 — Create the NLB Security Group

Create:

`HA-NLB-SG`

**Inbound rule:**

| Type | Protocol | Port | Source |
|---|---|---|---|
| HTTP | TCP | 80 | `0.0.0.0/0` |

This permits public HTTP access through the Network Load Balancer.

### Step 3 — Create the Application Security Group

Create:

`HA-App-SG`

**Inbound rules:**

| Type | Protocol | Port | Source |
|---|---|---|---|
| Custom TCP | TCP | 8002 | `HA-NLB-SG` |
| SSH | TCP | 22 | `HA-Bastion-SG` |

Application traffic is restricted to the Network Load Balancer, and administrative SSH traffic is restricted to the Bastion Host.

Do not open all TCP ports or allow application port 8002 from the entire internet.

### Step 4 — Create the Database Security Group

Create:

`HA-DB-SG`

**Inbound rules:**

| Type | Protocol | Port | Source |
|---|---|---|---|
| PostgreSQL | TCP | 5432 | `HA-App-SG` |
| SSH | TCP | 22 | `HA-Bastion-SG` |

This permits PostgreSQL traffic only from EC2 instances associated with the Application Security Group.

The database servers are deployed in private subnets and have no public IPv4 addresses.

### Step 5 — Verify the Security Groups

Using AWS CLI:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=HA-Bastion-SG,HA-NLB-SG,HA-App-SG,HA-DB-SG" \
  --region eu-north-1 \
  --query "SecurityGroups[*].{Name:GroupName,Inbound:IpPermissions}" \
  --output json
```

Verify that each security group permits only its intended inbound traffic.

### Security Considerations

- Security Groups are stateful, allowing response traffic for permitted connections.
- Referencing Security Groups instead of changing EC2 private IPs supports Auto Scaling.
- Public SSH access is restricted to the administrator's IP.
- The Bastion Host provides controlled administrative access.
- PostgreSQL is not directly exposed to the public internet.
- Security Group egress rules should also be reviewed according to the application's requirements.

**Note:** Application instances in this project are deployed in public subnets and have public IPv4 addresses. For a more production-oriented design, application instances could be moved to private subnets.




