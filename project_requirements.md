# Codex Implementation Brief — `karimaouaouda/per-host-observe`

## 1. Mission

Build a professional, production-oriented, low-complexity **per-VPS observability agent project**.

Target workflow:

```bash
git clone https://github.com/karimaouaouda/per-host-observe.git
cd per-host-observe

cp .env.example .env
nano .env

# Optional DB configs:
cp examples/postgres.example.env instances/postgres/my-app.env
nano instances/postgres/my-app.env

sudo sh check-configs.sh
sudo sh start.sh
```

Normal updates:

```bash
git pull
sudo sh check-configs.sh
sudo sh start.sh
```

The project must install and run **one Grafana Alloy process per VPS**, preferably through the official Linux package and `systemd`.

The centralized observability stack already exists:

```text
Grafana:
https://grafana.karimaouaouda.space

Prometheus remote-write ingress:
https://observability.karimaouaouda.space/prometheus/write

Loki push ingress:
https://observability.karimaouaouda.space/loki/push
```

The Prometheus/Loki ingestion paths are already protected by HTTPS + NGINX Basic Auth.

This repository must **not** deploy Grafana, Prometheus, Loki, NGINX, Mimir, Tempo, Pyroscope, or another central backend.

---

## 2. Architectural Constraint

Keep the host side deliberately small:

```text
VPS
│
├── NGINX                         existing host service
├── Docker                        existing
│   ├── application containers
│   ├── PostgreSQL containers
│   ├── MySQL containers
│   └── Redis containers
│
└── Grafana Alloy                 ONLY observability agent
    ├── CPU / RAM / disk / network
    ├── Docker/container metrics
    ├── Docker/application logs
    ├── NGINX access/error logs
    ├── HTTP RED metrics via Beyla
    ├── PostgreSQL metrics
    ├── MySQL metrics
    └── Redis metrics
```

Do **not** deploy standalone:

```text
node-exporter
cadvisor
postgres-exporter
mysqld-exporter
redis-exporter
promtail
beyla container
```

Use Alloy's embedded components.

---

## 3. Supported Platform — v1

Support only:

- Ubuntu / Debian Linux
- `systemd`
- Docker Engine
- host-level NGINX
- AMD64 / ARM64

Do not add fragile abstraction for every Linux distribution. Fail clearly on unsupported systems.

---

## 4. Deployment Model

Install Alloy directly on the VPS OS and run it as the official `systemd` service.

Do **not** run Alloy in Docker in v1.

Reasons:

- direct host metrics;
- direct NGINX log access;
- Docker socket access;
- easier eBPF/Beyla visibility;
- fewer host mounts/capabilities than a containerized agent;
- simple lifecycle management.

Expected lifecycle:

```bash
sudo systemctl start alloy
sudo systemctl stop alloy
sudo systemctl restart alloy
sudo systemctl status alloy
sudo journalctl -u alloy
```

Keep Alloy's HTTP server local only:

```text
127.0.0.1:12345
```

Never expose the Alloy UI/API publicly.

---

## 5. Required v1 Capabilities

| Requirement | Alloy component/mechanism | Default |
|---|---|---:|
| CPU / RAM / load | `prometheus.exporter.unix` | on |
| Disk/filesystem / disk I/O | `prometheus.exporter.unix` | on |
| Host network metrics | `prometheus.exporter.unix` | on |
| Docker/container metrics | `prometheus.exporter.cadvisor` | on |
| Docker container logs | `discovery.docker` + `loki.source.docker` | on |
| Application logs | Docker stdout/stderr | on |
| NGINX access/error logs | `loki.source.file` | on if files exist |
| HTTP RED metrics | `beyla.ebpf` | on, configurable |
| PostgreSQL | `prometheus.exporter.postgres` | when configured |
| MySQL | `prometheus.exporter.mysql` | when configured |
| Redis | `prometheus.exporter.redis` | when configured |
| Metrics transport | `prometheus.remote_write` | on |
| Logs transport | `loki.write` | on |

Do not implement tracing, Tempo, framework SDKs, Laravel queue/cache metrics, Kubernetes, or profiling in v1.

---

## 6. Repository Structure

Use a clear layout similar to:

```text
per-host-observe/
├── README.md
├── LICENSE
├── .env.example
├── .gitignore
│
├── check-configs.sh
├── start.sh
├── stop.sh
├── status.sh
│
├── scripts/
│   ├── common.sh
│   ├── install-alloy.sh
│   ├── render-config.sh
│   ├── deploy-config.sh
│   ├── configure-permissions.sh
│   ├── verify.sh
│   ├── upgrade-alloy.sh
│   └── uninstall.sh
│
├── alloy/
│   ├── templates/
│   │   ├── 00-base.alloy
│   │   ├── 10-outputs.alloy
│   │   ├── 20-host.alloy
│   │   ├── 30-docker-metrics.alloy
│   │   ├── 40-docker-logs.alloy
│   │   ├── 50-nginx-logs.alloy
│   │   └── 60-beyla.alloy
│   └── generated/
│       └── .gitkeep
│
├── instances/
│   ├── postgres/.gitkeep
│   ├── mysql/.gitkeep
│   └── redis/.gitkeep
│
├── examples/
│   ├── postgres.example.env
│   ├── mysql.example.env
│   ├── redis.example.env
│   └── docker-compose-labels.example.yml
│
└── docs/
    ├── architecture.md
    ├── configuration.md
    ├── database-monitoring.md
    ├── docker-labels.md
    ├── security.md
    ├── troubleshooting.md
    └── updating.md
```

Keep generated config separate from templates. Never require users to edit generated Alloy files.

---

## 7. User-Facing Commands

### Validate

```bash
sudo sh check-configs.sh
```

Non-destructive.

### Install / render / deploy / start

```bash
sudo sh start.sh
```

Must be idempotent.

It should:

1. validate configuration;
2. install minimal dependencies;
3. install Alloy if absent;
4. configure permissions;
5. render configuration to a staging directory;
6. run `alloy fmt`;
7. run `alloy validate`;
8. back up current live config;
9. atomically deploy new config;
10. configure/enable `systemd`;
11. restart/reload Alloy;
12. check readiness/health;
13. rollback config automatically if the new service fails;
14. print a concise final status.

### Stop

```bash
sudo sh stop.sh
```

Stop Alloy only. Preserve package/configuration.

### Status

```bash
sudo sh status.sh
```

Show service status, version, health, configured collectors, DB counts, and central connectivity.

All root scripts intended for these commands must be POSIX `sh` compatible.

---

## 8. Global `.env`

Create `.env.example`; Git-ignore `.env`.

Suggested interface:

```dotenv
# Identity
HOST_ID=my-vps-01
ENVIRONMENT=production
REGION=
DATACENTER=

# Central endpoints
GRAFANA_URL=https://grafana.karimaouaouda.space
PROMETHEUS_WRITE_URL=https://observability.karimaouaouda.space/prometheus/write
LOKI_WRITE_URL=https://observability.karimaouaouda.space/loki/push

# Per-VPS Basic Auth credentials
OBSERVABILITY_USERNAME=my-vps-01
OBSERVABILITY_PASSWORD=CHANGE_ME

# Never disable TLS verification by default.
TLS_INSECURE_SKIP_VERIFY=false

# Host
ENABLE_HOST_METRICS=true

# Docker
ENABLE_DOCKER_METRICS=true
ENABLE_DOCKER_LOGS=true
DOCKER_HOST=unix:///var/run/docker.sock

# Host NGINX
ENABLE_NGINX_LOGS=true
NGINX_ACCESS_LOG=/var/log/nginx/access.log
NGINX_ERROR_LOG=/var/log/nginx/error.log

# Beyla
ENABLE_BEYLA=true
BEYLA_CONTAINERS_ONLY=true
BEYLA_OPEN_PORTS=3000,8000-8999

# Local Alloy admin endpoint
ALLOY_HTTP_ADDRESS=127.0.0.1:12345
```

Install local secrets into a protected system path such as:

```text
/etc/per-host-observe/agent.env
```

Use restrictive ownership/permissions, e.g. `root:alloy` and `0640`.

Never print passwords in normal output and never pass secrets in CLI arguments.

---

## 9. Central Outputs

Metrics:

```text
https://observability.karimaouaouda.space/prometheus/write
```

Use `prometheus.remote_write` with Basic Auth.

Logs:

```text
https://observability.karimaouaouda.space/loki/push
```

Use `loki.write` with Basic Auth.

Use:

```text
OBSERVABILITY_USERNAME
OBSERVABILITY_PASSWORD
```

for both in v1.

TLS verification must remain enabled. Do not default to insecure TLS.

---

## 10. Identity and Labels

At minimum, attach low-cardinality identity:

```text
host
environment
```

For Docker telemetry preserve useful metadata where available:

```text
container
container_id
image
compose_project
compose_service
app
service
```

Recommended application Docker labels:

```yaml
labels:
  observability.app: "drovenai"
  observability.service: "backend"
```

Recommended app environment for Beyla identity:

```yaml
environment:
  OTEL_SERVICE_NAME: "drovenai-backend"
  OTEL_RESOURCE_ATTRIBUTES: "service.namespace=drovenai,deployment.environment.name=production"
```

Never put request IDs, user IDs, order IDs, session IDs, or arbitrary raw URL paths into Prometheus labels.

---

## 11. Host Metrics

Use `prometheus.exporter.unix`, not Node Exporter.

Collect normal Linux metrics only:

- CPU;
- memory;
- load;
- filesystem capacity;
- disk I/O;
- network interfaces/errors.

Scrape embedded targets with `prometheus.scrape` and forward to central remote write.

Apply `host` and `environment` labels consistently.

---

## 12. Docker Metrics

Use `prometheus.exporter.cadvisor`, not a standalone cAdvisor container.

Use the Docker endpoint:

```text
unix:///var/run/docker.sock
```

Allow only useful container labels where supported, for example:

```text
observability.app
observability.service
com.docker.compose.project
com.docker.compose.service
```

Document that Docker group access is security-sensitive and effectively root-equivalent.

---

## 13. Docker/Application Logs

Applications should preferably log to stdout/stderr.

Pipeline:

```text
Laravel / Node / worker
        ↓
stdout/stderr
        ↓
Docker
        ↓
discovery.docker
        ↓
loki.source.docker
        ↓
loki.relabel/process
        ↓
loki.write
        ↓
central Loki
```

Do not require per-app log file paths for normal Docker apps.

Map stable Docker metadata into useful Loki labels.

Avoid high-cardinality log labels.

---

## 14. NGINX Logs

NGINX runs on the host.

Default paths:

```text
/var/log/nginx/access.log
/var/log/nginx/error.log
```

Use `loki.source.file`.

Suggested labels:

```text
source=nginx
log_type=access|error
host=<HOST_ID>
environment=<ENVIRONMENT>
```

Do not over-engineer parsing in v1. Raw lines plus useful labels are acceptable.

Use filesystem ACLs so the `alloy` user can read the logs. Do not run Alloy as root just for log access. Preserve access across log rotation.

---

## 15. Beyla HTTP RED

Use Alloy's `beyla.ebpf`.

v1 exports **metrics only**, not traces:

```text
request rate
errors
duration/latency
HTTP method
status
route where supported
service identity
```

Default discovery should target Dockerized app services, not every host process.

Conceptually use current supported syntax equivalent to:

```text
containers_only=true
open_ports=<BEYLA_OPEN_PORTS>
```

Do not instrument `1-65535`.

Avoid host NGINX by default; the target is app-level RED behind NGINX.

Prefer `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES` from applications for service identity.

This is important for multiple PHP-FPM containers, which may otherwise all look like the same executable.

### Security

Beyla needs eBPF-related Linux capabilities.

Consult the **current** official Alloy/Beyla docs at implementation time.

Grant the smallest capability set necessary for this exact v1 feature set.

Do not silently run Alloy permanently as root.

If secure non-root eBPF operation cannot be established on the target kernel, fail with a useful explanation rather than silently escalating.


## 16. Database Configuration Model

A VPS can have zero, one, or many DB instances.

Do not make `.env` a giant DB list.

Use:

```text
instances/postgres/
instances/mysql/
instances/redis/
```

One real instance file = one monitored DB server/instance.

Real files are Git-ignored. Commit examples only.

Do **not** `source` or execute instance files as shell.

Parse only known `KEY=value` fields as data.

---

## 17. PostgreSQL

Example:

```text
instances/postgres/drovenai.env
```

```dotenv
NAME=drovenai
DSN=postgresql://observability:PASSWORD@127.0.0.1:15432/postgres?sslmode=disable
AUTODISCOVERY=true
APP=drovenai
SERVICE=postgres
```

Use `prometheus.exporter.postgres`.

Important:

```text
1 PostgreSQL server
└── 20 logical databases
```

should normally use one exporter component plus PostgreSQL database autodiscovery.

But:

```text
3 independent PostgreSQL servers/containers
```

should generate 3 separately labeled Alloy exporter components.

Sanitize `NAME` into a valid Alloy component label.

Use a dedicated monitoring account; do not use a DB superuser unless strictly required.

---

## 18. MySQL

Example:

```text
instances/mysql/shop.env
```

```dotenv
NAME=shop
DSN=observability:PASSWORD@(127.0.0.1:13306)/
APP=shop
SERVICE=mysql
```

Use `prometheus.exporter.mysql`.

Verify the current MySQL DSN syntax against official Alloy documentation. Do not assume PostgreSQL URL format.

Use one component per MySQL server.

Use a least-privilege monitoring user.

---

## 19. Redis

Example:

```text
instances/redis/drovenai.env
```

```dotenv
NAME=drovenai
ADDRESS=127.0.0.1:16379
PASSWORD=
APP=drovenai
SERVICE=redis
```

Use `prometheus.exporter.redis`.

Do not enable key scanning, per-key metrics, or other expensive/high-cardinality features by default.

Use one component per Redis instance.

---

## 20. Dockerized DB Connectivity

Alloy runs on the host OS, so database containers must be reachable from the host.

Do not recommend public DB ports.

Preferred pattern:

```yaml
services:
  postgres:
    ports:
      - "127.0.0.1:15432:5432"

  mysql:
    ports:
      - "127.0.0.1:13306:3306"

  redis:
    ports:
      - "127.0.0.1:16379:6379"
```

For multiple instances use different loopback ports.

Example:

```text
Postgres A -> 127.0.0.1:15432
Postgres B -> 127.0.0.1:25432
Redis A    -> 127.0.0.1:16379
Redis B    -> 127.0.0.1:26379
```

Do not depend on ephemeral Docker container IP addresses.

Do not modify application Compose files automatically; print required recommendations instead.

---

## 21. Generated Alloy Configuration

Implement `scripts/render-config.sh`.

Render to a **temporary staging directory**, not directly to the live config.

Runtime layout should be modular, for example:

```text
/etc/alloy/per-host-observe/
├── 00-base.alloy
├── 10-outputs.alloy
├── 20-host.alloy
├── 30-docker-metrics.alloy
├── 40-docker-logs.alloy
├── 50-nginx.alloy
├── 60-beyla.alloy
├── 70-postgres-drovenai.alloy
├── 71-postgres-shop.alloy
├── 80-mysql-shop.alloy
└── 90-redis-drovenai.alloy
```

Alloy supports loading a directory of `*.alloy` files as one config source. Use that capability.

Generated files must:

- say they are generated;
- identify the source file;
- be deterministic;
- contain useful comments;
- not be manually edited.

Run:

```bash
alloy fmt
alloy validate <generated-directory>
```

before deployment.

---

## 22. Atomic Deployment and Rollback

`start.sh` must never destroy a working config before validating the new one.

Required sequence:

```text
1. render temp config
2. format
3. validate
4. back up current live config
5. atomically replace live config
6. reload/restart Alloy
7. check /-/ready
8. check /-/healthy
9. if failure:
      restore previous config
      restart previous configuration
      report the failure
```

Store a small number of config backups under:

```text
/var/lib/per-host-observe/backups/
```

Do not back up central telemetry data.

---

## 23. `check-configs.sh`

Must be non-destructive.

Validate:

### Platform

- Linux;
- supported Debian/Ubuntu;
- systemd;
- root/sudo;
- architecture.

### Required tools

At minimum:

```text
curl
git
systemctl
docker
getent
sed
awk
grep
```

and only other minimal dependencies.

### `.env`

Check:

- exists;
- required variables are set;
- HTTPS URLs;
- password isn't `CHANGE_ME`;
- safe `HOST_ID`;
- non-empty environment;
- insecure TLS is not accidentally enabled.

### Central DNS/TLS/auth

Verify central DNS and TLS.

For authenticated ingestion checks, note that an empty POST may validly return a protocol `400`.

Interpret:

```text
401 / 403 -> authentication error
404       -> wrong NGINX path
TLS/DNS   -> connectivity/config error
400       -> endpoint may be reachable but payload is intentionally invalid
```

Do not send fake production metrics/logs by default.

### Docker

When Docker monitoring is enabled:

```text
docker info
/var/run/docker.sock
```

### NGINX

Validate configured log paths/parent directories and whether the `alloy` user can be granted safe read access.

### DB files

For every file:

- known keys only;
- required fields;
- unique `NAME`;
- valid sanitized Alloy identifier;
- no duplicate names;
- no secret printing.

Optional TCP reachability checks are acceptable.

### Beyla

Check kernel/capability prerequisites as practical.

Reject dangerously broad discovery configuration.

### Alloy

If installed:

```bash
alloy --version
alloy validate <rendered-temp-dir>
```

If absent, explain that final syntax validation occurs during `start.sh`.

Print `[OK]`, `[INFO]`, `[WARN]`, `[ERROR]` consistently and return non-zero on errors.

---

## 24. `start.sh`

Must be idempotent.

Pseudo-flow:

```text
require root
load and validate project settings
run preflight/checks
install minimal dependencies
install Alloy if missing
configure secure directories
configure Docker access
configure NGINX log ACLs
configure Beyla capabilities
render config to staging
alloy fmt
alloy validate
backup active config
deploy atomically
configure systemd
systemctl daemon-reload
systemctl enable alloy
restart/reload Alloy
verify health
print summary
```

Must **not**:

- `apt upgrade` the server;
- restart Docker;
- restart NGINX;
- restart databases;
- change firewall;
- change DNS;
- edit application Compose;
- change Certbot.

---

## 25. Alloy Installation

Use Grafana's official Linux package repository:

```text
https://apt.grafana.com
```

Do not use random binaries or unofficial packages.

Do not automatically upgrade Alloy every time `start.sh` runs.

Install when absent. Upgrades must be deliberate.

If version pinning is implemented, document the policy clearly.

---

## 26. systemd

Use the official Alloy service.

Do not edit vendor unit files directly.

Use drop-ins when needed.

Point Alloy at:

```text
/etc/alloy/per-host-observe
```

Keep state under the official/default location:

```text
/var/lib/alloy
```

Keep the HTTP listener at:

```text
127.0.0.1:12345
```

Document all systemd drop-ins, capabilities, and environment files.

---

## 27. Docker Permissions

Alloy needs Docker daemon access for discovery, logs, and cAdvisor.

Using the `docker` group is acceptable for v1 if it matches current official guidance:

```bash
sudo usermod -aG docker alloy
```

But clearly document:

> Docker group membership is effectively root-equivalent and is security-sensitive.

Restart Alloy after membership changes.

---

## 28. NGINX Log Permissions

Use ACLs.

Install the `acl` package if needed.

Grant only the `alloy` user read/traverse permissions to configured log paths.

Preserve access through log rotation.

Never use `chmod 777`.

Never make logs world-readable.

---

## 29. Beyla Permissions

This is security-sensitive.

Consult current official `beyla.ebpf` and Beyla security docs.

For v1 the intended use is:

- Dockerized apps;
- HTTP RED metrics;
- metrics only;
- no trace export.

Grant the smallest capability set required for that scope.

Document:

- capability names;
- why they are needed;
- how applied;
- how to remove them.

Verify Beyla actually starts.

Do not silently fall back to running Alloy as root.

---

## 30. Metrics Pipeline

Target architecture:

```text
prometheus.exporter.unix ─┐
prometheus.exporter.cadvisor ─┤
beyla.ebpf ────────────────┤
postgres/mysql/redis ───────┤
                           ▼
                   prometheus.scrape
                           │
                           ▼
                  prometheus.remote_write
                           │
                           ▼
https://observability.karimaouaouda.space/prometheus/write
```

Use clean component names and avoid duplicate scraping.

---

## 31. Logs Pipeline

```text
Docker ── discovery.docker ── loki.source.docker ─┐
                                                   │
NGINX access/error ── loki.source.file ────────────┤
                                                   ▼
                                         relabel/process
                                                   │
                                                   ▼
                                              loki.write
                                                   │
                                                   ▼
https://observability.karimaouaouda.space/loki/push
```

Do not over-engineer parsing in v1.

---

## 32. Self-Monitoring

Keep Alloy's HTTP server local.

Optionally scrape its own `/metrics` locally and forward useful agent health metrics to central Prometheus.

Use:

```text
host=<HOST_ID>
environment=<ENVIRONMENT>
service=alloy
```

Never expose port `12345` publicly.

---

## 33. Verification

Implement `scripts/verify.sh`.

At minimum:

```bash
systemctl is-active alloy
curl -f http://127.0.0.1:12345/-/ready
curl -f http://127.0.0.1:12345/-/healthy
```

Also verify:

- central DNS;
- central TLS;
- authenticated endpoint reachability;
- Docker access;
- NGINX log readability;
- configured exporter health;
- no obvious fatal journal errors.

Do not destroy/reinstall Alloy because one external DB is temporarily unavailable.

---

## 34. `status.sh`

Target human-readable output:

```text
Per-host Observability
────────────────────────────────────

Host
  ID:             app-vps-01
  Environment:    production

Alloy
  Installed:      yes
  Version:        1.x.x
  Service:        active
  Ready:          yes
  Healthy:        yes

Central
  Prometheus:     reachable
  Loki:           reachable
  Grafana:        https://grafana.karimaouaouda.space

Collectors
  Host metrics:   enabled
  Docker metrics: enabled
  Docker logs:    enabled
  NGINX logs:     enabled
  Beyla:          enabled

Databases
  PostgreSQL:     2
  MySQL:          1
  Redis:          2
```

Never print credentials or DSNs containing passwords.

---

## 35. Stop / Uninstall

`stop.sh` stops Alloy only.

An explicit `scripts/uninstall.sh` may remove project-owned agent configuration and permissions after confirmation.

It must never remove Docker, NGINX, databases, app data, or central services.

---

## 36. Recommended Application Docker Convention

Provide an example:

```yaml
services:
  backend:
    image: my-app

    environment:
      OTEL_SERVICE_NAME: my-app-backend
      OTEL_RESOURCE_ATTRIBUTES: service.namespace=my-app,deployment.environment.name=production

    labels:
      observability.app: my-app
      observability.service: backend
```

Explain that these are optional but strongly recommended for clean service identity in Beyla, Docker metrics/logs, and Grafana.

Apps do not need to join a special observability Docker network.


## 37. Documentation Requirements

`README.md` must explain:

### What the repo does

One Alloy agent per VPS for:

```text
host metrics
Docker metrics
Docker/app logs
NGINX logs
Beyla RED
PostgreSQL
MySQL
Redis
```

### Install

```bash
git clone https://github.com/karimaouaouda/per-host-observe.git
cd per-host-observe

cp .env.example .env
nano .env

sudo sh check-configs.sh
sudo sh start.sh
```

### Update

```bash
git pull
sudo sh check-configs.sh
sudo sh start.sh
```

### Status

```bash
sudo sh status.sh
```

### Agent logs

```bash
sudo journalctl -u alloy -f
```

Also document:

- DB instance examples;
- Docker app labels;
- architecture;
- security;
- troubleshooting;
- Alloy upgrades.

Common troubleshooting cases must include:

```text
Docker socket permission denied
NGINX log permission denied
Beyla capability missing
Prometheus ingress 401/403/404
Loki ingress 401/403/404
TLS verification failure
DB connection refused
Alloy validate failure
Alloy unhealthy component
```

Provide actionable commands.

---

## 38. Security Documentation

Create `docs/security.md`.

Cover:

### Per-host central credentials

Use a unique Basic Auth credential per VPS when possible.

Rotate it if the VPS is compromised.

### Docker group

Explicitly state the root-equivalent implications.

### eBPF/Beyla

Explain capabilities and least-privilege decisions.

### Database accounts

Use dedicated monitoring users.

Do not reuse application superusers just for exporter access.

### Local secrets

Protect:

```text
.env
instances/**/*.env
/etc/per-host-observe/
```

### DB networking

Host-mapped DB ports used by Alloy should bind to:

```text
127.0.0.1
```

not `0.0.0.0`.

### Alloy UI

Keep local only:

```text
127.0.0.1:12345
```

---

## 39. `.gitignore`

At minimum:

```gitignore
.env

instances/postgres/*.env
instances/mysql/*.env
instances/redis/*.env

!instances/postgres/.gitkeep
!instances/mysql/.gitkeep
!instances/redis/.gitkeep

alloy/generated/*
!alloy/generated/.gitkeep

*.local
*.tmp
.DS_Store
```

Examples must remain committed.

---

## 40. Shell Quality

Scripts must:

- be POSIX `sh` where user-facing;
- fail cleanly;
- quote variables;
- create temp dirs safely;
- clean with traps;
- avoid command injection;
- never print secrets;
- use clear status messages;
- return useful exit codes;
- contain comments for non-obvious logic.

Do not write one giant shell file. Put reusable logic in `scripts/common.sh`.

---

## 41. Never Execute Instance Config Files

Do **not** implement:

```sh
. instances/postgres/foo.env
```

Treat config as data.

Use a safe parser that:

- accepts `KEY=value`;
- permits only documented keys;
- skips comments/blank lines;
- rejects duplicates;
- never evaluates shell syntax.

Apply the same principle to global `.env` if practical.

---

## 42. Error Quality

Bad:

```text
Database failed.
```

Good:

```text
[ERROR] PostgreSQL instance "drovenai" cannot be reached at 127.0.0.1:15432.
        Check that its Docker service exposes:
        127.0.0.1:15432:5432
```

Bad:

```text
Beyla failed.
```

Good:

```text
[ERROR] Beyla is enabled but the required eBPF capability is unavailable.
        Review docs/security.md or disable it with ENABLE_BEYLA=false.
```

---

## 43. No Silent External Changes

Scripts must not:

- restart Docker;
- restart NGINX;
- restart DBs;
- edit app Compose files;
- delete volumes;
- run Docker prune;
- modify firewall;
- modify DNS;
- modify Certbot.

Print recommendations instead.

---

## 44. Upgrade Strategy

Do not automatically upgrade Alloy on each deploy.

If `scripts/upgrade-alloy.sh` exists, it must:

1. show current version;
2. require target version/explicit confirmation;
3. back up config;
4. upgrade;
5. validate against new binary;
6. restart;
7. verify;
8. print rollback guidance.

---

## 45. Testing

Add lightweight tests for:

- config parser;
- invalid/duplicate instance names;
- sanitization;
- secret redaction;
- deterministic config rendering.

When Alloy is available in CI, validate representative generated configurations:

```text
base only
PostgreSQL only
MySQL only
Redis only
all DB types
Beyla disabled
NGINX disabled
```

Use:

```bash
alloy fmt
alloy validate
```

CI must not require production endpoint access.

---

## 46. Professional Git Commits — Mandatory

Codex must commit logical subchanges while implementing.

Do **not** produce one giant final commit.

Use professional Conventional Commit-style messages.

Example sequence:

```text
chore: scaffold per-host observability repository

docs: define host agent architecture and configuration model

feat: add safe environment and instance config parsing

feat: add Alloy Linux installation workflow

feat: add Prometheus and Loki central outputs

feat: add Linux host metrics collection

feat: add Docker container metrics collection

feat: add Docker log discovery and forwarding

feat: add NGINX log collection

feat: add Beyla HTTP RED instrumentation

feat: add PostgreSQL exporter generation

feat: add MySQL exporter generation

feat: add Redis exporter generation

feat: add atomic Alloy configuration deployment

feat: add preflight and runtime verification

docs: add security and troubleshooting guides

test: add config rendering and validation coverage
```

Rules:

- commit after each coherent working subchange;
- avoid broken commits where practical;
- do not combine unrelated work;
- never commit secrets;
- review `git diff --staged` before each commit;
- use commit bodies for security/architecture decisions when useful;
- do not force-push;
- do not unnecessarily rewrite history;
- do not squash all work into one commit;
- final working tree must be clean.

At completion include:

```bash
git log --oneline --decorate -n 20
```

in the implementation report.

---

## 47. Codex Working Method

Before coding:

1. read this entire brief;
2. inspect repo state;
3. consult current official Grafana Alloy/Beyla docs;
4. create a short implementation plan;
5. implement in logical stages;
6. validate each stage;
7. commit each stage.

If component syntax or permission requirements are uncertain:

> **Do not guess. Check current official docs.**

Prefer current Grafana Alloy docs over old Grafana Agent/River examples.

---

## 48. Components to Verify Against Current Docs

Use current official syntax for:

```text
prometheus.exporter.unix
prometheus.exporter.cadvisor
prometheus.exporter.postgres
prometheus.exporter.mysql
prometheus.exporter.redis
prometheus.scrape
prometheus.remote_write

discovery.docker

loki.source.docker
loki.source.file
loki.relabel
loki.process
loki.write

beyla.ebpf
```

Do not install standalone equivalents unless current Alloy genuinely no longer supports the feature.

---

## 49. Definition of Done

### Repository

- [ ] professional structure;
- [ ] `.env.example`;
- [ ] secrets Git-ignored;
- [ ] Postgres/MySQL/Redis examples;
- [ ] complete docs.

### Installation

- [ ] `sudo sh check-configs.sh` works;
- [ ] `sudo sh start.sh` is idempotent;
- [ ] Alloy installed from official repo;
- [ ] systemd service enabled;
- [ ] starts at boot.

### Host

- [ ] CPU;
- [ ] RAM;
- [ ] disk/filesystem;
- [ ] network.

### Docker

- [ ] containers discovered;
- [ ] container metrics;
- [ ] stdout/stderr logs;
- [ ] useful labels.

### NGINX

- [ ] access logs;
- [ ] error logs;
- [ ] no world-readable permission hack.

### Beyla

- [ ] HTTP RED metrics;
- [ ] bounded discovery;
- [ ] documented least-privilege capabilities;
- [ ] no Tempo/tracing dependency.

### Databases

- [ ] zero DBs works;
- [ ] multiple PostgreSQL servers;
- [ ] PostgreSQL logical DB autodiscovery;
- [ ] multiple MySQL;
- [ ] multiple Redis;
- [ ] add/remove instance via one config file + rerun `start.sh`.

### Central

- [ ] metrics reach `/prometheus/write`;
- [ ] logs reach `/loki/push`;
- [ ] Basic Auth;
- [ ] TLS verified;
- [ ] secrets not logged.

### Safety

- [ ] validate before activation;
- [ ] atomic deployment;
- [ ] rollback on bad restart;
- [ ] no Docker/NGINX/DB restarts;
- [ ] no firewall/DNS changes.

### Operations

- [ ] useful `status.sh`;
- [ ] safe `stop.sh`;
- [ ] update docs;
- [ ] troubleshooting docs.

### Git

- [ ] logical professional commits;
- [ ] no secrets in history;
- [ ] clean final tree.

---

## 50. Desired Final Experience

Fresh VPS:

```bash
git clone https://github.com/karimaouaouda/per-host-observe.git
cd per-host-observe

cp .env.example .env
nano .env

# Optional:
cp examples/postgres.example.env instances/postgres/myapp.env
nano instances/postgres/myapp.env

sudo sh check-configs.sh
sudo sh start.sh
sudo sh status.sh
```

Adding another DB later:

```bash
cp examples/postgres.example.env instances/postgres/second.env
nano instances/postgres/second.env

sudo sh check-configs.sh
sudo sh start.sh
```

No additional exporter container should be needed.

---

## 51. Final Architecture

```text
                         ONE VPS
─────────────────────────────────────────────────

NGINX access/error logs ───────────────────────┐
                                               │
Docker                                         │
├── App A ─ stdout/stderr ─────────────────────┤
├── App B ─ stdout/stderr ─────────────────────┤
├── PostgreSQL ─ metrics ──────────────────────┤
├── MySQL ─ metrics ───────────────────────────┤
└── Redis ─ metrics ───────────────────────────┤
                                               │
Linux host CPU/RAM/disk/network ───────────────┤
                                               │
Dockerized HTTP apps ─ Beyla RED ──────────────┤
                                               ▼
                                          Grafana Alloy
                                         /             \
                                     metrics            logs
                                        │                │
                                        ▼                ▼
                              /prometheus/write      /loki/push
                                        \                /
                                         \              /
                          observability.karimaouaouda.space
```

The project succeeds when a VPS has **one observability agent to operate**, while that agent covers host, Docker, logs, HTTP RED, PostgreSQL, MySQL, and Redis observability.

---

## 52. Official Documentation — Source of Truth

Codex must consult current official docs during implementation.

### Alloy core

- Linux install  
  https://grafana.com/docs/alloy/latest/set-up/install/linux/

- Run on Linux/systemd  
  https://grafana.com/docs/alloy/latest/set-up/run/linux/

- Linux permissions  
  https://grafana.com/docs/alloy/latest/access_permissions/linux/

- Configure Alloy  
  https://grafana.com/docs/alloy/latest/configure/

- CLI validate  
  https://grafana.com/docs/alloy/latest/reference/cli/validate/

- HTTP health endpoints  
  https://grafana.com/docs/alloy/latest/reference/http/

### Metrics

- Unix exporter  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/

- cAdvisor exporter  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.cadvisor/

- PostgreSQL exporter  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.postgres/

- MySQL exporter  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.mysql/

- Redis exporter  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.redis/

- Prometheus scrape  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/

- Prometheus remote write  
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.remote_write/

### Docker/logs

- Docker discovery  
  https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.docker/

- Docker logs  
  https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/

- File logs  
  https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.file/

- Loki write  
  https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/

- Docker monitoring guide  
  https://grafana.com/docs/alloy/latest/monitor/monitor-docker-containers/

### Beyla

- Alloy Beyla component  
  https://grafana.com/docs/alloy/latest/reference/components/beyla/beyla.ebpf/

- Service discovery  
  https://grafana.com/docs/beyla/latest/configure/service-discovery/

- Security/capabilities  
  https://grafana.com/docs/beyla/latest/security/

---

## Final Instruction

Build this as an **operator-quality but deliberately small repository**.

Prioritize:

```text
simple deployment
easy configuration
secure defaults
minimal moving parts
repeatability
safe updates
clear rollback
good troubleshooting
professional Git history
```

Do not introduce infrastructure just because larger observability platforms commonly use it.

The defining constraint is:

> **One VPS should need only one Grafana Alloy service for host, Docker, logs, HTTP RED, PostgreSQL, MySQL, and Redis observability.**
