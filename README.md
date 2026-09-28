# Per-host Observe

A production-oriented, low-complexity Grafana Alloy deployment for one Ubuntu or Debian VPS. It sends host and Docker metrics, Docker/application logs, host NGINX logs, Beyla HTTP RED metrics, and optional PostgreSQL, MySQL, and Redis metrics to an existing Prometheus/Loki backend. It does not deploy a central observability stack or standalone exporters.

## Quick start

```sh
git clone https://github.com/karimaouaouda/per-host-observe.git
cd per-host-observe
cp .env.example .env
nano .env

# Optional database instances:
cp examples/postgres.example.env instances/postgres/my-app.env

sudo sh check-configs.sh
sudo sh start.sh
```

`start.sh` installs Alloy from Grafana's official APT repository only when absent, renders and validates a staging configuration, deploys it atomically, and automatically restores the previous configuration if health checks fail.

Common operations:

```sh
sudo sh status.sh
sudo journalctl -u alloy -f
sudo sh stop.sh

# Update project configuration/code:
git pull
sudo sh check-configs.sh
sudo sh start.sh

# Deliberate Alloy package upgrade:
sudo sh scripts/upgrade-alloy.sh
```

The local Alloy interface is bound to `127.0.0.1:12345`. Do not expose it publicly.

## Configuration

Never commit `.env` or files under `instances/*/*.env`. Each database file describes one independently reachable server; PostgreSQL autodiscovery can collect all logical databases on that server. See [configuration](docs/configuration.md), [database monitoring](docs/database-monitoring.md), and [Docker conventions](docs/docker-labels.md).

## Design and operations

- [Architecture](docs/architecture.md)
- [Security](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Updating](docs/updating.md)

## Development

The tests exercise parser safety, validation, deterministic rendering, and secret separation without requiring root or a running Alloy service:

```sh
sh tests/run.sh
```

Production installation and end-to-end health verification require a supported VPS because they exercise `apt`, systemd, Docker, ACLs, eBPF capabilities, and the configured remote endpoints.
