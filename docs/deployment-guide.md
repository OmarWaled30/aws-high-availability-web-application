
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



