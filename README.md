# Todo App – Classic 3-Tier AWS Architecture (EC2 + ALB + RDS)

> **Scope of this README:** A classic EC2-based 3-tier architecture (web / app / DB) on AWS.  


---

## 1. Project Overview

### What this project is

This is a **production-style 3-tier web application** on AWS, built as a learning and portfolio project. The stack:

- **Web tier** – Nginx on EC2 behind a **public Application Load Balancer**
- **App tier** – Node.js API on EC2 behind an **internal Application Load Balancer**
- **Data tier** – Amazon RDS PostgreSQL in private subnets
- **Bastion host** – for SSH and `psql` into the private network

Right now the app is a simple Todo API. The focus is on **infrastructure, networking, and troubleshooting**.

### Why I built it

I wanted something that:

- Looks like a **real-world legacy/enterprise architecture**, not just a single EC2 box
- Forces me to work with:
  - VPC, subnets, route tables, NAT, IGW
  - Security groups vs NACLs
  - ALB health checks, target groups, and user data failures
- Gives me a solid baseline to compare against a **future serverless version** (cost, complexity, operations)

---

## 2. High-Level Architecture

### Diagram

> 📸 **Screenshot 1 – Overall architecture**

<img width="5438" height="6225" alt="3 Teir AWS" src="https://github.com/user-attachments/assets/45d74580-d350-493e-bd82-fe936dc43717" />

---

## 3. Naming & Inventory

### 3.1 Naming conventions

| Type               | Pattern                    | Example                        |
|--------------------|---------------------------|--------------------------------|
| VPC                | `todo-vpc-*`              | `todo-vpc-main`                |
| Subnets            | `todo-subnet-<tier>-<az>` | `todo-subnet-app-a`            |
| Route tables       | `todo-rt-*`               | `todo-rt-public`               |
| IGW / NAT          | `todo-igw-*`, `todo-nat-*`| `todo-igw-main`, `todo-nat-a`  |
| Security groups    | `todo-sg-*`               | `todo-sg-app-ec2`              |
| ALBs               | `todo-alb-*`              | `todo-alb-web`, `todo-alb-app` |
| Target groups      | `todo-tg-*`               | `todo-tg-web`, `todo-tg-app`   |
| Auto Scaling group | `todo-asg-*`              | `todo-asg-web`, `todo-asg-app` |
| Launch template    | `todo-lt-*`               | `todo-lt-web`, `todo-lt-app`   |
| Bastion            | `todo-ec2-bastion`        | `todo-ec2-bastion`             |
| RDS DB             | `todo-rds-*`              | `todo-rds-postgres`            |

---

## 4. VPC & Networking

### 4.1 VPC and subnets

**VPC:** `todo-vpc-main` – `10.0.0.0/16`

| Layer | Name                    | AZ          | CIDR         | Public? | Purpose                       |
|-------|-------------------------|-------------|--------------|---------|-------------------------------|
| Public | `todo-subnet-public-a` | eu-west-1a  | 10.0.1.0/24  | Yes     | Bastion, web ALB              |
| Public | `todo-subnet-public-b` | eu-west-1b  | 10.0.2.0/24  | Yes     | Web ALB (HA)                  |
| App    | `todo-subnet-app-a`    | eu-west-1a  | 10.0.11.0/24 | No      | Web + App EC2 (AZ A)          |
| App    | `todo-subnet-app-b`    | eu-west-1b  | 10.0.12.0/24 | No      | Web + App EC2 (AZ B)          |
| DB     | `todo-subnet-db-a`     | eu-west-1a  | 10.0.21.0/24 | No      | RDS primary                   |
| DB     | `todo-subnet-db-b`     | eu-west-1b  | 10.0.22.0/24 | No      | RDS standby (Multi-AZ)        |

> 📸 **Screenshot 2 – VPC + subnets**  
<img width="1609" height="618" alt="Screenshot 2025-12-05 114937" src="https://github.com/user-attachments/assets/95a5b597-8f46-4b70-9a05-7737d297b8cf" />


### 4.2 Route tables & gateways

| Route table      | Subnets attached                 | Routes                                                                 |
|------------------|----------------------------------|------------------------------------------------------------------------|
| `todo-rt-public` | `public-a`, `public-b`           | `10.0.0.0/16 → local`; `0.0.0.0/0 → todo-igw-main` (IGW)              |
| `todo-rt-app`    | `app-a`, `app-b`                 | `10.0.0.0/16 → local`; `0.0.0.0/0 → todo-nat-a` (NAT GW)              |
| `todo-rt-db`     | `db-a`, `db-b`                   | `10.0.0.0/16 → local` only (no internet route)                         |
<img width="1648" height="204" alt="Screenshot 2025-12-05 115426" src="https://github.com/user-attachments/assets/516f78d3-40e9-431c-8593-783ad2e7c84a" />

- **Internet Gateway:** `todo-igw-main`
- **NAT Gateway:** `todo-nat-a` in `todo-subnet-public-a` (shared by app subnets)

### 4.3 NACLs

- NACLs are essentially **allow-all in/out** on each subnet.
- All network security is handled by **security groups**.
- This makes debugging much simpler while learning the architecture.

> 📸 **Screenshot 3 – Route table**  
> Route Tables → `todo-rt-app` showing default route to `todo-nat-a`.
<img width="1648" height="473" alt="Screenshot 2025-12-05 115506" src="https://github.com/user-attachments/assets/dda3302e-836a-4f48-9588-217cc97dd74a" />

---

## 5. Security Groups & Access Model

### 5.1 Security group matrix

| SG               | Attached to             | Inbound rules (key)                                               |
|------------------|-------------------------|--------------------------------------------------------------------|
| `todo-sg-bastion` | Bastion EC2             | SSH `22` from trusted IPs / CloudShell                            |
| `todo-sg-web-alb` | Web ALB (public)        | HTTP `80` from `0.0.0.0/0`                                        |
| `todo-sg-web-ec2` | Web EC2 ASG             | `80` from `todo-sg-web-alb`; `22` from `todo-sg-bastion`          |
| `todo-sg-app-alb` | App ALB (internal)      | `80` from `todo-sg-web-ec2` (and temporarily bastion for debug)   |
| `todo-sg-app-ec2` | App EC2 ASG             | `3000` from `todo-sg-app-alb`; `22` from `todo-sg-bastion`        |
| `todo-sg-rds`     | RDS PostgreSQL          | `5432` from `todo-sg-app-ec2` and `todo-sg-bastion`               |

Outbound on all SGs: allow all (default).

### 5.2 Access principles

- Only the **web ALB** is internet-facing.
- Web EC2 is only reachable:
  - From web ALB on 80
  - From bastion on 22 (SSH)
- App EC2 is only reachable:
  - From app ALB on 3000
  - From bastion on 22
- RDS is only reachable:
  - From app EC2 on 5432
  - From bastion on 5432 (for direct `psql`)

> 📸 **Screenshot 4 – SG detail**  
> EC2 → Security Groups → `todo-sg-app-ec2` showing source = `todo-sg-app-alb` on port 3000.
<img width="1333" height="344" alt="Screenshot 2025-12-05 115808" src="https://github.com/user-attachments/assets/93aa3d3c-b9db-4414-99d1-9b3dcab211ea" />
<img width="1638" height="502" alt="Screenshot 2025-12-05 115843" src="https://github.com/user-attachments/assets/e7b08f39-779f-4939-bd23-7e3e8e9b89f9" />

---

## 6. Ports & Traffic Hierarchy

### 6.1 End-to-end port flow

```text
Client browser
  → Web ALB (todo-alb-web)        : HTTP 80
    → Web EC2 (Nginx)             : HTTP 80
      → App ALB (todo-alb-app)    : HTTP 80 (backend listener)
        → App EC2 (Node API)      : HTTP 3000
          → RDS Postgres          : TCP 5432
```

Admin/debug paths:

```text
CloudShell / Local IP
  → Bastion EC2                    : SSH 22
    → Web/App EC2                  : SSH 22
    → RDS                          : TCP 5432 (psql)
```

### 6.2 Port table

| Layer       | Source SG           | Dest SG            | Port | Protocol | Purpose                            |
|------------|---------------------|--------------------|------|----------|------------------------------------|
| Internet   | `0.0.0.0/0`         | `todo-sg-web-alb`  | 80   | TCP      | Public HTTP to web ALB             |
| Web tier   | `todo-sg-web-alb`   | `todo-sg-web-ec2`  | 80   | TCP      | ALB → Nginx                        |
| App entry  | `todo-sg-web-ec2`   | `todo-sg-app-alb`  | 80   | TCP      | Nginx → internal app ALB           |
| App tier   | `todo-sg-app-alb`   | `todo-sg-app-ec2`  | 3000 | TCP      | App ALB → Node API                 |
| DB tier    | `todo-sg-app-ec2`   | `todo-sg-rds`      | 5432 | TCP      | Node API → Postgres                |
| Admin SSH  | `todo-sg-bastion`   | web/app EC2 SGs    | 22   | TCP      | Bastion → private EC2              |
| Admin DB   | `todo-sg-bastion`   | `todo-sg-rds`      | 5432 | TCP      | Bastion → RDS (`psql`)             |

Later in Phase 2 (or beyond), HTTPS on 443 will be added to the web ALB, but Phase 1 is intentionally HTTP-only for simplicity.

---

## 7. Bastion & Database

### 7.1 Bastion host

- **Instance:** `todo-ec2-bastion`  
- **Subnet:** `todo-subnet-public-a` (public)  
- **SG:** `todo-sg-bastion`  
- Used for:
  - SSH into private EC2 instances
  - `psql` into RDS for schema setup and debugging

From CloudShell / local:

```bash
ssh -i todo-key-bastion.pem ec2-user@<bastion-public-ip>
```

From the bastion:

```bash
psql "host=<rds-endpoint> port=5432 dbname=todo_db user=todo_user"
```
<img width="996" height="444" alt="Screenshot 2025-12-05 120411" src="https://github.com/user-attachments/assets/6c0fbb5c-4325-4ac9-96c5-e1cfe6d7e001" />

If this connects, routing + SGs + NACLs for DB path are good.

### 7.2 RDS PostgreSQL

- **Engine:** PostgreSQL  
- **Identifier:** `todo-rds-postgres`  
- **Multi-AZ:** Enabled  
- **Subnets:** `todo-subnet-db-a` and `todo-subnet-db-b`  
- **SG:** `todo-sg-rds`  

Core table:

```sql
CREATE TABLE todos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  title       text NOT NULL,
  description text,
  is_done     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  due_at      timestamptz
);
```

> 📸 **Screenshot 5 – RDS DB**  
<img width="912" height="272" alt="Screenshot 2025-12-05 120934" src="https://github.com/user-attachments/assets/21ef1bf1-fa99-4f6c-a744-b9214eb9ec5e" />

<img width="1198" height="304" alt="Screenshot 2025-12-05 141559" src="https://github.com/user-attachments/assets/a4e452bd-ac12-4b20-9684-980d6f75fe49" />

---

## 8. App Tier – Internal ALB + Node.js API

### 8.1 App ALB & target group

- **ALB:** `todo-alb-app`  
  - Scheme: **Internal**  
  - Subnets: app-a, app-b  
  - SG: `todo-sg-app-alb`
- **Listener:** HTTP 80 → `todo-tg-app`
- **Target group `todo-tg-app`:**
  - Target type: Instances
  - Port: 3000
  - Health check: `HTTP /health` on port 3000

### 8.2 App Auto Scaling Group

- **ASG:** `todo-asg-app`  
- **Launch template:** `todo-lt-app`  
- **Type:** `t3.micro`  
- **Subnets:** `todo-subnet-app-a`, `todo-subnet-app-b`  
- **SG:** `todo-sg-app-ec2`

User data installs Node, pulls app code, and sets up `todo-app` systemd service listening on 3000.

### 8.3 Node.js API

Endpoints:

- `GET /health`  
  - Runs `SELECT 1` against RDS  
  - Used by app ALB health checks

- `GET /api/todos`  
  - Returns a list of todos (initially for a fixed test `user_id`)

- `POST /api/todos`  
  - Accepts `{ "title": "..." }` and inserts into `todos`

On an app instance:

```bash
sudo systemctl status todo-app
sudo journalctl -u todo-app -n 50
sudo ss -lntp | grep ':3000' || echo "nothing on 3000"

curl -v http://localhost:3000/health
curl -v http://localhost:3000/api/todos
```

> 📸 **Screenshot 6 – App target group**  

<img width="1165" height="781" alt="Screenshot 2025-12-05 141949" src="https://github.com/user-attachments/assets/d73174d6-1804-4457-a526-214a24686430" />

---

## 9. Web Tier – Public ALB + Nginx

### 9.1 Web ALB & target group

- **ALB:** `todo-alb-web`  
  - Scheme: **Internet-facing**  
  - Subnets: public-a, public-b  
  - SG: `todo-sg-web-alb`
- **Listener:** HTTP 80 → `todo-tg-web`
- **Target group `todo-tg-web`:**
  - Target type: Instances
  - Port: 80
  - Health check: `HTTP /health` on port 80

### 9.2 Web Auto Scaling Group

- **ASG:** `todo-asg-web`  
- **Launch template:** `todo-lt-web`  
- **Type:** `t3.micro`  
- **Subnets:** `todo-subnet-app-a`, `todo-subnet-app-b` (private)  
- **SG:** `todo-sg-web-ec2`

User data installs Nginx and drops a custom `nginx.conf`.

### 9.3 Nginx configuration (simplified)

Nginx:

- `/health` → plain `OK` for ALB checks
- `/api/*` → proxied to app ALB

```nginx
http {
    upstream app_backend {
        server internal-todo-alb-app-XXXX.eu-west-1.elb.amazonaws.com:80;
    }

    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        location /health {
            access_log off;
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /api/ {
            proxy_pass http://app_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

On a web instance:

```bash
sudo nginx -t
sudo systemctl status nginx
sudo ss -lntp | grep ':80' || echo "nothing on 80"

curl -v http://localhost/health
curl -v http://localhost/
```

> 📸 **Screenshot 7 – Web target group**  

<img width="1054" height="783" alt="Screenshot 2025-12-05 142134" src="https://github.com/user-attachments/assets/b648de80-fadd-4da6-a96c-eab5f79e2069" />

---

## 10. End-to-End Testing

From bastion → app ALB:

```bash
APP_ALB_DNS="internal-todo-alb-app-XXXX.eu-west-1.elb.amazonaws.com"

curl -v http://$APP_ALB_DNS/health
curl -v http://$APP_ALB_DNS/api/todos
```

From internet → web ALB:

```bash
WEB_ALB_DNS="todo-alb-web-XXXX.eu-west-1.elb.amazonaws.com"

curl -v http://$WEB_ALB_DNS/health
curl -v http://$WEB_ALB_DNS/api/health
curl -v http://$WEB_ALB_DNS/api/todos
```

> 📸 **Screenshot 8 – Bastion terminal**  

<img width="650" height="212" alt="Screenshot 2025-12-05 143912" src="https://github.com/user-attachments/assets/fdf9b0ed-6ada-454c-9449-dfd3545e2d37" />

---

## 11. Issues, Root Causes & Fixes

### 11.1 Summary table

| Symptom                                           | Root cause                                   | Fix                                                    | Takeaway                                                    |
|--------------------------------------------------|----------------------------------------------|--------------------------------------------------------|-------------------------------------------------------------|
| `psql` from bastion to RDS **timed out**         | DB subnet NACL was too restrictive           | Opened NACLs (allow all), enforced control via SGs     | Always check SG + NACL when you see timeouts               |
| App ALB targets **unhealthy (timeout)**          | Node API not running (user data failed)      | SSH → `systemctl status`, fixed service & restart      | Confirm the app is listening locally before blaming ALB    |
| `curl localhost:3000` → connection refused       | `todo-app` systemd unit missing/invalid      | Wrote proper systemd service, `daemon-reload`, enabled | Don’t assume user data ran; verify with `systemctl`        |
| Nginx wouldn’t start (`invalid parameter ":80"`) | Bad nginx.conf (typo in `listen` or upstream)| Replaced with clean config, `nginx -t` then restart    | If ALB says unhealthy, check the web server logs first     |
| App instances came up as `m1` not `t3.micro`     | ASG using old launch template version        | Pointed ASG to latest LT version and recycled instances| Always check ASG → LT version when instance type is wrong  |
| SSH to new app/web instances failing             | Wrong key pair in launch template            | Updated LT with `todo-key-bastion`, refreshed ASG      | Key pair mismatch is a classic headache                    |
| Web ALB `/api/*` → `502 Bad Gateway`             | Nginx proxy or backend health misconfigured  | Fixed upstream block and ensured app targets healthy   | `502` usually means web tier can’t reach backend           |

### 11.2 Troubleshooting flow I followed

I ended up with a consistent pattern:

1. **On the instance itself**
   - `systemctl status` to see if the process is even running  
   - `curl http://localhost:<port>` to test the service locally

2. **From inside the VPC (bastion)**
   - `curl http://<internal-alb-dns>/health` to test ALB → instances

3. **In the console**
   - Check target group health + reason (timeout vs 5xx)
   - Confirm SGs are **SG → SG**, not wide-open CIDRs

4. **Only then** look at:
   - Route tables, NACLs, NAT, etc.

---

## 12. Cost Awareness

These numbers are approximate, based on on-demand pricing and typical US/EU regions. Exact costs vary slightly by region and should be checked in the AWS Pricing Calculator.

### 12.1 EC2 instances

Instance type: **t3.micro** (~$0.0104/hour for Linux on-demand).

- Monthly (24×7): 0.0104 × 24 × 30 ≈ **$7.50 per instance per month**

Phase 1 EC2 footprint:

- Web tier ASG: 2 × t3.micro → ~**$15/month**
- App tier ASG: 2 × t3.micro → ~**$15/month**
- Bastion: 1 × t3.micro → ~**$7.50/month**

**Rough EC2 total:** **~$37–40/month**

(Excluding any free tier / credits.)

### 12.2 RDS PostgreSQL

Instance type: **db.t3.micro**, on-demand around **$0.018/hour** in many regions for PostgreSQL.

- Monthly (24×7): 0.018 × 24 × 30 ≈ **$13/month** for compute
- Plus storage (e.g. 20 GB gp2) and Multi-AZ overhead

To be safe, budgeting **~$20–25/month** for RDS in this setup is reasonable.

### 12.3 Application Load Balancers (2× ALB)

Application Load Balancer pricing has:  

- **Base hourly charge**: roughly **$0.0225–$0.0252 per ALB-hour**, depending on region  
- **LCU usage**: extra cost per LCU-hour (for connections / data / rules)

For low dev traffic you’re mostly paying the **base hourly**:

- Per ALB base cost: ~0.0252 × 24 × 30 ≈ **$18–19/month**
- Two ALBs (web + app): ≈ **$36–38/month**

With very low LCUs, the usage component stays small.

### 12.4 NAT Gateway

NAT Gateway pricing:

- Hourly: around **$0.045/hour** in cheaper regions  
- Data processing: around **$0.045/GB** in the same regions

Monthly (24×7): 0.045 × 24 × 30 ≈ **$32–33/month** just to have one NAT up, plus data processing.

For small dev workloads, the NAT is often one of the **most expensive single items** relative to everything else.

### 12.5 Elastic IP / Public IPv4 cost

As of 2024, AWS charges **$0.005 per hour** for public IPv4 addresses (including Elastic IPs), attached or idle.

That’s roughly:

- **$0.005 × 24 × 30 ≈ $3.60/month per public IPv4**

In this project, likely public IPv4s:

- Bastion Elastic IP
- NAT Gateway public IP (behind the scenes)

So just having two public IPv4s costs ≈ **$7.20/month** on top of the normal EC2/NAT/ALB costs.

### 12.6 Rough total (Phase 1, 24×7)

Ballpark monthly:

- EC2: **$37–40**
- RDS: **$20–25**
- 2× ALB: **$36–38**
- NAT GW: **$32–33**
- 2× public IPv4/EIP: **$7–8**
- EBS + CloudWatch + data: a few dollars

**Total:** roughly **$130–150/month** for a small, always-on 3-tier stack, without any discounts.

And that’s the whole point for Phase 2: **serverless can dramatically reduce the idle cost** by killing most of these fixed hourly charges.

---

## 13. Phase 2 Preview – Serverless Migration

Phase 1 proves:

- I can design and operate a **classic 3-tier EC2 architecture**:
  - 2× ALBs
  - 2× EC2 ASGs
  - Bastion
  - NAT
  - RDS

Next, in **Phase 2**, I’ll:

1. Convert this into a **serverless architecture**:
   - Frontend: React SPA hosted on **S3 + CloudFront**
   - API: **API Gateway + Lambda** instead of app ALB + EC2
   - DB: Either keep RDS (with RDS Proxy) or explore Aurora Serverless / DynamoDB

2. Compare:
   - **Cost**: fixed hourly infra (EC2, NAT, ALB, EIP) vs pay-per-use
   - **Operations**: patching + scaling EC2 vs Lambda & managed services
   - **Security**: SG-heavy vs more managed edges (CloudFront, WAF, IAM auth)


