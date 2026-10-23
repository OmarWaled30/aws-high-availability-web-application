# AWS High Availability Web Application — Testing Results

## 1. Overview

This document presents the testing and validation results for the AWS High Availability Web Application project.

The objective was to evaluate application availability, Network Load Balancer behavior, automatic instance replacement, CPU-based scaling, and PostgreSQL connectivity.

**Environment:**

- AWS Region: `eu-north-1`
- Load Balancer: `HA-WebApp-NLB`
- Target Group: `HA-App-TG`
- Auto Scaling Group: `HA-WebApp-ASG`
- Application Port: `8002`
- Auto Scaling CPU Target: `50%`

**Testing Tools:** Grafana Cloud k6, Linux `stress-ng`, Amazon CloudWatch, AWS CLI, PowerShell, and PostgreSQL `psql`.

---

## 2. HTTP Load Testing Using Grafana k6

Several HTTP load tests were performed against the public Network Load Balancer endpoint.

| Test | Virtual Users | Duration | Requests | HTTP Failures | P95 Response Time |
|---|---:|---|---:|---:|---:|
| Baseline | 5 | 50 seconds | 167 | 0 | 125 ms |
| Moderate load | 10 | 60 seconds | 411 | 0 | 125 ms |
| Higher load | 20 | 60 seconds | 817 | 0 | 125 ms |

### Observations

- All recorded HTTP requests succeeded.
- The application continued responding through the NLB.
- Throughput increased as the number of virtual users increased.
- The measured P95 response time was approximately 125 ms in the reported tests.

These results demonstrate successful application availability under the tested workloads. They do not establish the maximum capacity of the system.

---

## 3. Application Failover Test

### Objective

Verify that the Network Load Balancer continues serving requests when an application instance becomes unhealthy.

### Procedure

1. Started a Grafana k6 load test against the NLB.
2. Connected to one application EC2 instance.
3. Stopped its Python application service using `systemctl`.
4. Observed CloudWatch target-health metrics and k6 results.
5. Restored the application service after the test.

### Results

| Measurement | Recorded result |
|---|---|
| HTTP requests | 818 |
| HTTP failures | 0 |
| P95 response time | Approximately 125 ms |
| Healthy NLB targets | Decreased from 2 to 1 |
| Unhealthy NLB targets | Increased from 0 to 1 |

### Conclusion

The NLB continued serving successful HTTP requests during the observed service interruption.

This supports application-tier fault tolerance under the tested conditions. It does not guarantee zero failures for every client connection or failure scenario.

---

## 4. EC2 Auto Scaling Self-Healing Test

### Objective

Verify that the Auto Scaling Group automatically replaces a terminated EC2 application instance.

### Procedure

1. Configured the ASG with a desired capacity of two.
2. Terminated an ASG-managed EC2 instance.
3. Observed the ASG activity history.
4. Verified that a replacement EC2 instance was launched.
5. Verified that the replacement registered with the NLB target group and became healthy.

### Result

**Passed — Automatic instance replacement verified.**

During troubleshooting, the ASG target group association was found to be missing. After attaching `HA-App-TG`, replacement instances registered automatically.

---

## 5. CPU-Based Automatic Scale-Out Test

### Objective

Verify that the Auto Scaling Group increases application capacity during sustained CPU demand.

### Configuration

| Setting | Value |
|---|---|
| Minimum capacity | 2 |
| Initial desired capacity | 2 |
| Maximum capacity | 4 |
| Policy type | Target tracking |
| CPU target | 50% |
| Instance vCPUs | 2 per original application instance |

### Test Command

Executed on both application instances:

```bash
sudo stress-ng --cpu 2 --cpu-load 80 --timeout 10m --metrics-brief
```

### Observed Results

| Metric | Result |
|---|---|
| App Server 1 CPU snapshot | 78.3% |
| App Server 2 CPU snapshot | Approximately 80.4% |
| Initial desired capacity | 2 |
| Peak desired capacity | 4 |
| Additional EC2 instances | 2 |
| Peak healthy NLB targets | 4 |

The AWS-managed high-CPU alarm triggered the target-tracking policy.

**Result: Passed — Automatic scale-out from 2 to 4 instances.**

---

## 6. CPU-Based Automatic Scale-In Test

### Objective

Verify that AWS reduces excess EC2 capacity after CPU demand decreases.

### Procedure

1. Allowed the CPU stress workload to stop.
2. Observed CPU utilization decrease.
3. Inspected the AWS-managed low-CPU CloudWatch alarm.
4. Reviewed ASG activity history and instance lifecycle states.
5. Verified the group returned to its baseline capacity.

### Observed Results

| Metric | Result |
|---|---|
| Low CPU utilization | Approximately 0.16% |
| Low-CPU alarm | ALARM |
| Initial desired capacity | 4 |
| Intermediate desired capacity | 3 |
| Final desired capacity | 2 |

The ASG automatically selected excess application instances for termination.

The activity history also showed an instance waiting for load-balancer connection draining.

**Result: Passed — Automatic scale-in from 4 to 2 instances.**

---

## 7. Application Availability During Scale-In

### Objective

Verify that the NLB continues serving application requests while ASG-managed instances are being removed.

### PowerShell Test

```powershell
1..10 | ForEach-Object {
    curl.exe -s -o NUL -w "%{http_code}`n" http://YOUR_NLB_DNS/
    Start-Sleep -Seconds 2
}
```

### Results

| Measurement | Result |
|---|---|
| Requests sent | 10 |
| HTTP 200 responses | 10 |
| HTTP errors observed | 0 |

**Result: Passed — 10/10 HTTP requests succeeded.**

This is a successful availability spot check, not proof of zero downtime under all traffic conditions.

---

## 8. PostgreSQL Connectivity Tests

### Objective

Verify secure, authenticated PostgreSQL connectivity from application EC2 instances in both Availability Zones to both private database servers.

### Database Configuration

- PostgreSQL 16
- Database: `ha_project`
- Login role: `ha_app_user`
- Authentication: SCRAM-SHA-256
- PostgreSQL port: 5432
- Application subnet ranges: `10.0.1.0/24` and `10.0.2.0/24`

### Test Query

```sql
SELECT COUNT(*) FROM public.demo_records;
```

### Connectivity Matrix

| Source | DB Server 1 | DB Server 2 |
|---|---|---|
| App EC2 — eu-north-1a | Passed | Passed |
| App EC2 — eu-north-1b | Passed | Passed |

All four authenticated queries succeeded and returned a count of one.

**Result: Passed — 4/4 authenticated PostgreSQL connectivity tests.**

This verifies database connectivity through PostgreSQL clients. The Python HTTP service does not yet perform database queries.

---

## 9. Troubleshooting Summary

| Issue | Root cause | Resolution |
|---|---|---|
| EC2 bootstrap failure | Blank line preceding `#!/bin/bash` | Corrected User Data and Launch Template |
| Replacement target not registered | ASG missing NLB target group association | Attached `HA-App-TG` |
| CPU scaling initially not triggered | Insufficient average CPU utilization | Increased CPU workers on both instances |
| Delayed scale-in | CloudWatch evaluation and connection draining | Inspected alarm and scaling activity |
| PostgreSQL TCP connection refused | Listening only on localhost | Enabled private-IP listening |
| Remote PostgreSQL authentication unavailable | Missing `pg_hba.conf` rules | Added restricted application subnet rules |
| PostgreSQL password failure | Incorrect password entry | Retried with valid credentials |
| Missing PostgreSQL client | Client package not installed | Installed `postgresql-client` |

---

## 10. Overall Test Summary

| Test | Final result |
|---|---|
| HTTP load testing | Passed |
| Application failover | Passed |
| EC2 Auto Scaling self-healing | Passed |
| CPU-based scale-out | Passed |
| CPU-based scale-in | Passed |
| NLB availability during scale-in | Passed |
| Database TCP connectivity | Passed |
| PostgreSQL authentication | 4/4 passed |

## 11. Important Limitations

- The PostgreSQL servers are independent; database replication and automated failover are not implemented.
- The Python HTTP application does not currently query PostgreSQL.
- Application EC2 instances are deployed in public subnets.
- The public NLB listener uses HTTP over TCP rather than HTTPS/TLS.
- Tests were performed using controlled workloads and do not establish a production availability SLA.
- Database client and test-tool installations performed manually on ASG instances are not automatically included in future instance launches.

## 12. Conclusion

The AWS infrastructure successfully demonstrated load balancing, application-level failure handling, EC2 instance replacement, CPU-driven automatic scaling, monitoring, and authenticated connectivity to private PostgreSQL instances.

The experiments provided practical evidence of how multiple AWS services work together to support application-tier resilience and dynamic capacity management.
