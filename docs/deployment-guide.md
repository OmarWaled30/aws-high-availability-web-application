
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

## 4. Deploy and Configure the Bastion Host

### Overview

A Bastion Host provides a controlled entry point for administrative SSH access to EC2 instances within the VPC.

In this project, the Bastion Host is deployed in a public subnet and is used to access both application servers and private PostgreSQL database servers.

### Step 1 — Launch the Bastion Host

Navigate to **AWS Console → EC2 → Instances → Launch instance**.

Configure:

| Setting | Configuration |
|---|---|
| Instance name | `HA-Bastion-Host` |
| Operating system | Ubuntu Server |
| VPC | `HA-WebApp-VPC` |
| Subnet | `HA-Public-1a` |
| Public IPv4 address | Enabled |
| Security Group | `HA-Bastion-SG` |
| Key pair | `HA-WebApp-Key` |

Choose an appropriate instance type for the lab.

Ensure the Bastion Host has SSH access only from the administrator's authorized public IP address.

### Step 2 — Connect Using PuTTY

On Windows:

1. Open PuTTY.
2. Enter the Bastion Host's public IPv4 address.
3. Set the connection type to SSH and the port to `22`.
4. Configure the appropriate SSH private key or SSH agent.
5. Connect using the username `ubuntu`.

Example:

```text
ubuntu@BASTION_PUBLIC_IP
```

Accept the SSH host key only after verifying its fingerprint through a trusted source.

### Step 3 — Connect to an Application Instance

From the Bastion Host, connect using the application's private IP address:

```bash
ssh ubuntu@APP_PRIVATE_IP
```

Example from the verified deployment:

```bash
ssh ubuntu@10.0.1.142
```

The application instance's Security Group must allow SSH from `HA-Bastion-SG`.

Auto Scaling can replace application instances, so their private IP addresses should be discovered from EC2 or Auto Scaling before connecting.

### Step 4 — Connect to the Private Database Servers

Both database servers are deployed in private subnets without public IPv4 addresses.

From the Bastion Host, connect to DB Server 1:

```bash
ssh ubuntu@10.0.11.50
```

Connect to DB Server 2:

```bash
ssh ubuntu@10.0.12.68
```

The database Security Group allows SSH connections from the Bastion Security Group.

### Step 5 — Verify SSH Connectivity

On each destination instance, run:

```bash
hostname
```

Then:

```bash
ip -4 addr show
```

Confirm that the hostname and private IPv4 address match the intended EC2 instance.

To exit a private instance and return to the Bastion Host:

```bash
exit
```

Run `exit` again to disconnect from the Bastion Host.

### Security Best Practices

- Restrict Bastion SSH ingress to a trusted administrator IP.
- Use SSH keys instead of password authentication.
- Never commit private SSH keys to GitHub.
- Verify SSH host fingerprints before trusting new hosts.
- Avoid copying private keys unnecessarily onto the Bastion Host; use an approved SSH agent or controlled jump-host configuration.
- Review administrative access regularly.

For production environments, AWS Systems Manager Session Manager is another option for administrative access without relying on a publicly accessible SSH Bastion Host.

### Verification Result

SSH connectivity was successfully tested from the Bastion Host to both application instances and both private PostgreSQL servers.

The Bastion Host enables controlled administrative access while the database tier remains without public IPv4 addresses.

## 5. Create the EC2 Launch Template and Deploy the Application

### Overview

The application tier uses an EC2 Launch Template to standardize application instance configuration.

EC2 User Data automates the initial setup of each new instance by installing Python, creating the application files, configuring a systemd service, and starting the application.

This is essential for EC2 Auto Scaling because newly launched instances must become functional without manual SSH configuration.

### Step 1 — Create the Launch Template

Navigate to **AWS Console → EC2 → Launch Templates → Create launch template**.

Configure:

| Setting | Configuration |
|---|---|
| Launch Template name | `HA-App-LaunchTemplate` |
| AMI | Ubuntu Server (tested with Ubuntu 26.04) |
| Instance type | Small EC2 instance appropriate for the lab |
| Key pair | `HA-WebApp-Key` |
| Security Group | `HA-App-SG` |
| User Data | Bootstrap script from the repository |

Leave subnet selection to the Auto Scaling Group so instances can be launched across both Availability Zones.

### Step 2 — Configure User Data

Under **Advanced details → User data**, paste the contents of:

`scripts/app-user-data.sh`

The script performs the following actions:

1. Updates Ubuntu package metadata.
2. Installs Python 3.
3. Creates `/opt/ha-webapp`.
4. Creates the Python HTTP application.
5. Creates the `ha-webapp.service` systemd unit.
6. Enables and starts the application service.
7. Verifies that the service is active.

**Important:** The script must begin with `#!/bin/bash` as its first characters, without a blank line or UTF-8 BOM before the shebang.

The project originally encountered a bootstrapping error caused by a blank line before the shebang. Correcting the script and updating the Launch Template resolved this issue.

### Step 3 — Understand the Application

The application source code is available at:

`app/server.py`

It uses Python's built-in `ThreadingHTTPServer` and listens on:

`0.0.0.0:8002`

Each HTTP response includes:

- EC2 hostname.
- Server timestamp.
- Request counter.
- Unique request ID.
- Client IP address.
- Requested path.

The response helps identify which EC2 instance handled a request.

### Step 4 — Configure systemd

The systemd unit is provided in:

`systemd/ha-webapp.service`

It uses the following configuration:

```ini
[Unit]
Description=HA Web App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ha-webapp
ExecStart=/usr/bin/python3 -u /opt/ha-webapp/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

The service starts automatically during boot and is restarted if the application process exits.

### Step 5 — Verify Application Deployment

After launching a test application instance from the Launch Template, connect through the Bastion Host.

Check the service:

```bash
sudo systemctl is-active ha-webapp
```

Expected:

```text
active
```

Check the listening port:

```bash
sudo ss -lntp | grep 8002
```

Test the application locally:

```bash
curl http://localhost:8002
```

A successful response includes:

```text
AWS High Availability Web Application
Hostname: ...
Port: 8002
Message: Hello from EC2!
```

### Step 6 — Troubleshoot Bootstrapping

If the application isn't running, inspect the service and cloud-init logs:

```bash
sudo systemctl status ha-webapp
```

```bash
sudo journalctl -u ha-webapp --no-pager -n 50
```

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
```

Verify that the User Data script was executed successfully.

For this project, the corrected working configuration was saved as **Launch Template version 2**.

### Step 7 — Verify the Launch Template Using AWS CLI

```bash
aws ec2 describe-launch-templates \
  --launch-template-names HA-App-LaunchTemplate \
  --region eu-north-1 \
  --query "LaunchTemplates[*].{Name:LaunchTemplateName,DefaultVersion:DefaultVersionNumber,LatestVersion:LatestVersionNumber}" \
  --output table
```

The verified deployment used version `2` as both the default and latest version.

### Deployment Notes

- User Data executes during the EC2 instance's initial initialization under the normal cloud-init configuration.
- New Auto Scaling instances receive the application configuration automatically.
- The application doesn't require external Python packages.
- The current Python web application is a demonstration HTTP service and doesn't yet query PostgreSQL.
- Instance bootstrap should be tested after any Launch Template changes before being used for production scaling.

**Verification result:** Automatic application initialization was successfully tested on newly launched EC2 instances.
**Note:** Application instances in this project are deployed in public subnets and have public IPv4 addresses. For a more production-oriented design, application instances could be moved to private subnets.
## 6. Configure the Network Load Balancer and Target Group

### Overview

The Network Load Balancer (NLB) provides a single public endpoint for the application and distributes incoming TCP connections across healthy EC2 instances.

The application listens on port `8002`, while the NLB accepts incoming client traffic on port `80`.

The infrastructure uses:

- Load Balancer: `HA-WebApp-NLB`
- Target Group: `HA-App-TG`
- Listener: TCP port `80`
- Target protocol: TCP port `8002`
- Health check: HTTP `/`
- Target type: EC2 Instance

### Step 1 — Create the Target Group

Navigate to **AWS Console → EC2 → Target Groups → Create target group**.

Configure:

| Setting | Configuration |
|---|---|
| Target type | Instances |
| Target group name | `HA-App-TG` |
| Protocol | TCP |
| Port | `8002` |
| VPC | `HA-WebApp-VPC` |
| Health check protocol | HTTP |
| Health check path | `/` |
| Health check port | Traffic port |

Set the health check thresholds:

| Setting | Value |
|---|---|
| Healthy threshold | 5 |
| Unhealthy threshold | 2 |

Create the target group.

For an Auto Scaling deployment, configure the ASG to manage target registration rather than relying on manually registered instances.

### Step 2 — Create the Network Load Balancer

Navigate to **EC2 → Load Balancers → Create load balancer**.

Select **Network Load Balancer**.

Configure:

| Setting | Configuration |
|---|---|
| Name | `HA-WebApp-NLB` |
| Scheme | Internet-facing |
| IP address type | IPv4 |
| VPC | `HA-WebApp-VPC` |
| Availability Zones | `eu-north-1a`, `eu-north-1b` |
| Subnets | `HA-Public-1a`, `HA-Public-2b` |
| Security Group | `HA-NLB-SG` |

Create a listener:

| Listener setting | Value |
|---|---|
| Protocol | TCP |
| Port | `80` |
| Default action | Forward to `HA-App-TG` |

Create the load balancer.

### Step 3 — Configure Application Security

Ensure `HA-App-SG` permits:

| Protocol | Port | Source |
|---|---|---|
| TCP | 8002 | `HA-NLB-SG` |

This allows the NLB to reach the application instances.

The application instances must run the `ha-webapp` service and accept TCP connections on port `8002`.

### Step 4 — Integrate the Target Group with Auto Scaling

After creating `HA-WebApp-ASG`, open:

**EC2 → Auto Scaling Groups → HA-WebApp-ASG → Integrations → Load balancing → Edit**

Attach the existing target group:

`HA-App-TG`

Save the configuration.

This enables automatically launched ASG instances to register with the target group and terminating instances to deregister.

**Troubleshooting note:** During the project, an instance was initially replaced successfully by Auto Scaling but wasn't automatically registered with the NLB target group. Attaching `HA-App-TG` to the Auto Scaling Group resolved the issue.

### Step 5 — Verify Target Health Using AWS CLI

Retrieve the target group ARN:

```bash
aws elbv2 describe-target-groups \
  --names HA-App-TG \
  --region eu-north-1 \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text
```

Then inspect registered targets:

```bash
aws elbv2 describe-target-health \
  --target-group-arn YOUR_TARGET_GROUP_ARN \
  --region eu-north-1 \
  --query "TargetHealthDescriptions[*].{Instance:Target.Id,Port:Target.Port,State:TargetHealth.State}" \
  --output table
```

At baseline, the expected configuration contains two healthy EC2 targets on port `8002`.

During CPU-based scale-out, the number of healthy targets can increase as new instances are launched and pass health checks.

### Step 6 — Test the Public Application Endpoint

Copy the DNS name from:

**EC2 → Load Balancers → HA-WebApp-NLB → Details**

Run:

```bash
curl -i http://YOUR_NLB_DNS/
```

Expected:

```text
HTTP/1.1 200 OK

AWS High Availability Web Application
Hostname: ...
Port: 8002
Message: Hello from EC2!
```

Repeat the request to observe application responses while checking target health.

### Step 7 — Verify Load Balancer Availability

During the project, load testing and controlled failure experiments were performed to validate application availability.

In a separate scale-in availability check, 10 consecutive HTTP requests through the NLB returned status `200`.

This result demonstrates successful availability during the tested interval, but it doesn't guarantee zero downtime in all conditions.

### Important Notes

- The NLB operates at Layer 4 and forwards TCP connections to the application.
- The HTTP health check verifies that the application responds successfully on `/`.
- The target group's deregistration delay permits existing connections to drain during scale-in.
- EC2 Auto Scaling must be associated with the target group for automatic target registration.
- The public endpoint currently uses HTTP rather than HTTPS/TLS.
- A Network Load Balancer can distribute connections between targets, but individual requests over a persistent TCP connection may continue using the same target.

**Verification Result:** The NLB successfully distributed application traffic, detected application target health, and maintained service availability during the tested scaling and failover scenarios.




