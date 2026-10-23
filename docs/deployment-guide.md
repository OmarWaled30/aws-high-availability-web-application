
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

1. Create the VPC and subnets.
2. Configure the Internet Gateway, NAT Gateway, and route tables.
3. Create the Security Groups.
4. Launch and configure the Bastion Host.
5. Create the EC2 Launch Template using the bootstrap script.
6. Deploy the application using EC2 Auto Scaling.
7. Configure the Network Load Balancer and Target Group.
8. Deploy and configure the PostgreSQL database servers.
9. Configure CloudWatch monitoring.
10. Validate application availability, scaling, and database connectivity.
