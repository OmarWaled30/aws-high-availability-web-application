
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

## 7. Configure EC2 Auto Scaling

### Overview

Amazon EC2 Auto Scaling automatically adjusts the number of application EC2 instances according to demand and replaces instances that become unhealthy.

The Auto Scaling Group uses an EC2 Launch Template to deploy the Python application automatically across two Availability Zones.

### Step 1 — Create the Auto Scaling Group

Navigate to **AWS Console → EC2 → Auto Scaling Groups → Create Auto Scaling group**.

Configure:

| Setting | Configuration |
|---|---|
| Auto Scaling Group | `HA-WebApp-ASG` |
| Launch Template | `HA-App-LaunchTemplate` |
| Launch Template version | `2` |
| VPC | `HA-WebApp-VPC` |
| Subnet 1 | `HA-Public-1a` |
| Subnet 2 | `HA-Public-2b` |
| Minimum capacity | `2` |
| Desired capacity | `2` |
| Maximum capacity | `4` |

The ASG spans two Availability Zones to improve application availability.

**Deployment note:** During the original lab, two existing EC2 application instances were attached to the ASG. For a fresh deployment, the ASG can launch its initial instances automatically using the Launch Template.

### Step 2 — Attach the NLB Target Group

During ASG creation, under **Load balancing**, select:

**Attach to an existing load balancer → Choose from your load balancer target groups**

Select:

`HA-App-TG`

This allows new application instances to register automatically with the NLB and lets terminating instances deregister during scale-in.

### Step 3 — Enable ELB Health Checks

Navigate to:

**EC2 → Auto Scaling Groups → HA-WebApp-ASG → Details → Health checks → Edit**

Configure:

| Setting | Value |
|---|---|
| Health check type | ELB |
| Health check grace period | 300 seconds |

ELB health checks allow the ASG to consider NLB target health in addition to EC2 health.

### Step 4 — Configure Target Tracking

Open:

**HA-WebApp-ASG → Automatic scaling → Create dynamic scaling policy**

Configure:

| Setting | Value |
|---|---|
| Policy type | Target tracking |
| Policy name | `Target Tracking Policy` |
| Metric | Average CPU utilization |
| Target value | `50%` |
| Disable scale-in | False |
| Instance warmup | Use the group's configured/default behavior |

AWS automatically creates CloudWatch alarms for the target-tracking policy.

**Note:** The verified ASG had no explicit default instance warmup and used a default cooldown of 300 seconds. The target-tracking policy did not specify a separate warmup value.

### Step 5 — Verify the ASG Configuration

Run:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names HA-WebApp-ASG \
  --region eu-north-1 \
  --query "AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,HealthCheck:HealthCheckType,Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}}" \
  --output json
```

Expected baseline:

- Minimum: 2
- Desired: 2
- Maximum: 4
- Health check: ELB
- Two instances in `InService` state
- Both instances marked `Healthy`

### Step 6 — Test Automatic Instance Replacement

A controlled self-healing test was performed by terminating an ASG-managed EC2 instance.

The Auto Scaling Group automatically launched a replacement instance.

After confirming the target group integration, the replacement registered with `HA-App-TG` and became healthy.

**Result:** Automatic instance replacement verified.

### Step 7 — Test CPU-Based Scale-Out

CPU stress was generated on both application EC2 instances using `stress-ng`.

```bash
sudo stress-ng --cpu 2 --cpu-load 80 --timeout 10m --metrics-brief
```

The command was executed on both original application instances.

Observed CPU utilization increased to approximately 78–80%.

The high-CPU target-tracking alarm triggered an increase in desired capacity:

**2 → 4 instances**

AWS successfully launched two additional application instances, and all four instances became healthy NLB targets.

### Step 8 — Test Automatic Scale-In

After `stress-ng` stopped, CPU utilization decreased to approximately 0.16%.

The low-CPU target-tracking alarm entered the `ALARM` state.

AWS automatically reduced desired capacity:

**4 → 3 → 2 instances**

Instances selected for termination entered the connection-draining process before being removed from the target group.

No manual desired-capacity change was required.

### Step 9 — Verify Application Availability During Scale-In

Ten HTTP requests were sent through the NLB using Windows PowerShell:

```powershell
1..10 | ForEach-Object {
    curl.exe -s -o NUL -w "%{http_code}`n" http://YOUR_NLB_DNS/
    Start-Sleep -Seconds 2
}
```

All ten requests returned HTTP status `200`.

**Result:** Application availability was maintained throughout the observed request sample during scale-in.

This test does not guarantee zero downtime under every workload or failure scenario.

### Step 10 — Monitor Scaling Activities

Navigate to:

**EC2 → Auto Scaling Groups → HA-WebApp-ASG → Activity history**

Inspect scaling activities to verify:

- The scaling policy that triggered each action.
- Desired-capacity changes.
- EC2 instance launch and termination events.
- Connection-draining status.
- Successful completion of scaling operations.

Enable Auto Scaling Group metrics collection when needed and monitor:

- `GroupDesiredCapacity`
- `GroupInServiceInstances`
- `GroupTotalInstances`

These metrics were added to the `HA-WebApp-Monitoring` CloudWatch dashboard.

### Troubleshooting Lessons

During implementation, several issues were identified and resolved:

1. **Launch Template User Data failure:** A blank line before `#!/bin/bash` prevented correct execution. The script was corrected and saved in Launch Template version 2.
2. **Missing NLB target registration:** The Auto Scaling Group was initially missing the target group association. Attaching `HA-App-TG` resolved the problem.
3. **Insufficient CPU workload:** One CPU worker did not generate enough average CPU utilization to trigger scaling. Two workers on each two-vCPU instance produced sufficient CPU demand.
4. **Delayed scale-in:** AWS required sustained low-CPU CloudWatch datapoints before triggering the low-CPU alarm. Connection draining added time to instance termination.
5. **Health check configuration:** The ASG initially used EC2 health checks. ELB health checks were enabled afterward to include NLB target health.

### Verified Results

| Test | Result |
|---|---|
| Self-healing | Passed |
| Automatic target registration | Passed |
| CPU-based scale-out | 2 → 4 |
| Automatic scale-in | 4 → 2 |
| Final baseline | 2 healthy application instances |
| NLB availability during scale-in | 10/10 HTTP 200 |

**Important:** These tests verify application-tier Auto Scaling and availability behavior. The PostgreSQL servers are independent and do not provide automatic database replication or failover.

## 8. Deploy and Configure Private PostgreSQL Database Servers

### Overview

This project uses two PostgreSQL 16 database servers deployed on Amazon EC2 in separate private subnets.

Both databases are independently managed and are accessible from the application EC2 instances through the VPC's internal network.

**Important:** These servers do not use PostgreSQL replication or automatic database failover. The two databases are independent.

### Step 1 — Launch the Database EC2 Instances

Navigate to **AWS Console → EC2 → Instances → Launch instance**.

Configure the database instances as follows:

| Setting | Database Server 1 | Database Server 2 |
|---|---|---|
| Name | `HA-DB-Server-1` | `HA-DB-Server-2` |
| OS | Ubuntu Server 24.04 LTS | Ubuntu Server 24.04 LTS |
| Availability Zone | eu-north-1a | eu-north-1b |
| Subnet | HA-Private-1a | HA-Private-2b |
| Private IP (verified deployment) | 10.0.11.50 | 10.0.12.68 |
| Public IPv4 address | None | None |
| Security Group | HA-DB-SG | HA-DB-SG |
| SSH key pair | HA-WebApp-Key | HA-WebApp-Key |

For a new deployment, private IP addresses may differ.

### Step 2 — Connect Through the Bastion Host

Connect to the Bastion Host using SSH.

From the Bastion Host, connect to each database server using its private IP:

```bash
ssh ubuntu@10.0.11.50
```

Or:

```bash
ssh ubuntu@10.0.12.68
```

### Step 3 — Install PostgreSQL

On both database servers, install PostgreSQL 16 from an appropriate package repository:

```bash
sudo apt-get update
sudo apt-get install -y postgresql-16
```

Verify installation:

```bash
sudo systemctl is-active postgresql
```

Check database readiness:

```bash
sudo -u postgres pg_isready
```

Expected results:

```text
active
/var/run/postgresql:5432 - accepting connections
```

### Step 4 — Create the Sample Database

On each database server, open PostgreSQL:

```bash
sudo -u postgres psql
```

Create the database:

```sql
CREATE DATABASE ha_project;
```

Connect to it:

```sql
\c ha_project
```

Create a sample table for testing:

```sql
CREATE TABLE demo_records (
    id SERIAL PRIMARY KEY,
    message TEXT NOT NULL
);
```

Insert a sample record:

```sql
INSERT INTO demo_records (message)
VALUES ('Hello from PostgreSQL');
```

Verify:

```sql
SELECT COUNT(*) FROM demo_records;
```

Exit:

```sql
\q
```

The verified project contained one record in `demo_records` on each database server. The sample schema shown here is an illustrative reproducible configuration; the original table definition was not independently captured.

### Step 5 — Configure PostgreSQL to Listen on Its Private IP

During troubleshooting, PostgreSQL was found to be listening only on:

`127.0.0.1:5432`

This caused remote TCP connection attempts from application servers to fail with:

`Connection refused`

To enable private network access, configure PostgreSQL to listen on its private IP address.

On DB Server 1:

```bash
sudo -u postgres psql -c \
"ALTER SYSTEM SET listen_addresses = 'localhost,10.0.11.50';"
```

On DB Server 2:

```bash
sudo -u postgres psql -c \
"ALTER SYSTEM SET listen_addresses = 'localhost,10.0.12.68';"
```

Restart PostgreSQL on each server:

```bash
sudo systemctl restart postgresql
```

Verify:

```bash
sudo ss -lntp | grep 5432
```

Expected: PostgreSQL listens on both `127.0.0.1:5432` and the server's private IPv4 address on port `5432`.

### Step 6 — Create a Dedicated Application Database User

On each database server:

```bash
sudo -u postgres psql
```

Create the login role:

```sql
CREATE ROLE ha_app_user WITH LOGIN;
```

Set a strong password interactively:

```sql
\password ha_app_user
```

Grant database access:

```sql
GRANT CONNECT ON DATABASE ha_project TO ha_app_user;
```

Connect to the database:

```sql
\c ha_project
```

Grant the permissions required for the sample read-only query:

```sql
GRANT USAGE ON SCHEMA public TO ha_app_user;
GRANT SELECT ON TABLE public.demo_records TO ha_app_user;
```

Exit:

```sql
\q
```

Do not save the database password in the GitHub repository.

### Step 7 — Configure PostgreSQL Client Authentication

Back up the PostgreSQL authentication configuration:

```bash
sudo cp /etc/postgresql/16/main/pg_hba.conf \
  /etc/postgresql/16/main/pg_hba.conf.bak
```

Edit the file:

```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Add:

```text
host    ha_project    ha_app_user    10.0.1.0/24    scram-sha-256
host    ha_project    ha_app_user    10.0.2.0/24    scram-sha-256
```

These rules allow authentication by `ha_app_user` from the two application subnet ranges.

The AWS database Security Group separately restricts TCP 5432 ingress to EC2 instances using `HA-App-SG`.

Reload PostgreSQL:

```bash
sudo systemctl reload postgresql
```

Check for configuration errors:

```bash
sudo -u postgres psql -c \
"SELECT line_number, error FROM pg_hba_file_rules WHERE error IS NOT NULL;"
```

Expected:

```text
(0 rows)
```

### Step 8 — Verify TCP Connectivity from the Application Tier

From an application EC2 instance, test TCP connectivity:

```bash
nc -zv -w 3 10.0.11.50 5432
nc -zv -w 3 10.0.12.68 5432
```

Both connections should succeed.

If `nc` is missing:

```bash
sudo apt-get install -y netcat-openbsd
```

### Step 9 — Test Authenticated PostgreSQL Queries

Install the PostgreSQL client on application instances if needed:

```bash
sudo apt-get update
sudo apt-get install -y postgresql-client
```

Test DB Server 1:

```bash
psql -h 10.0.11.50 -p 5432 \
  -U ha_app_user -d ha_project -W \
  -c "SELECT COUNT(*) FROM public.demo_records;"
```

Test DB Server 2:

```bash
psql -h 10.0.12.68 -p 5432 \
  -U ha_app_user -d ha_project -W \
  -c "SELECT COUNT(*) FROM public.demo_records;"
```

Enter the appropriate database password when prompted.

The same tests were executed successfully from both application EC2 instances.

### Verified Connectivity Matrix

| Application Source | DB Server 1 | DB Server 2 |
|---|---|---|
| App EC2 — eu-north-1a | Passed | Passed |
| App EC2 — eu-north-1b | Passed | Passed |

All four tests successfully authenticated and executed a SELECT query, returning one record.

### Troubleshooting Lessons

**Connection refused:** PostgreSQL was listening only on localhost. Configuring `listen_addresses` to include the private IP resolved the TCP connectivity failure.

**Authentication not permitted:** PostgreSQL's `pg_hba.conf` initially allowed local connections only. Adding restricted host rules enabled authentication from the application subnets.

**Password authentication failed:** An initial remote login failed due to an incorrect password entry. Retrying with the correct credentials succeeded.

**Missing PostgreSQL client:** One application EC2 instance did not initially have a functional `psql` client. Installing `postgresql-client` resolved the problem.

### Security and Architecture Limitations

- Database EC2 instances have no public IPv4 addresses.
- PostgreSQL inbound traffic is restricted by the database Security Group.
- Application database permissions are limited to the sample read-only query.
- PostgreSQL credentials should be managed securely.
- PostgreSQL client connections in this lab were not explicitly configured to require TLS.
- Client tools installed manually on Auto Scaling instances will not automatically persist when instances are replaced unless included in their launch configuration.
- The Python HTTP application does not currently execute PostgreSQL queries.
- The two PostgreSQL databases are independent, without replication or automated failover.

**Verification Result:** PostgreSQL services, local SQL access, private TCP connectivity, authentication, and all four application-to-database SQL connections were successfully tested.

