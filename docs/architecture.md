# Architecture

One official Grafana Alloy systemd service runs as the unprivileged `alloy` account on each VPS. Alloy reads host resources, the Docker socket, Docker logs, and NGINX files; embedded exporters collect database metrics. Metrics pass through one identity relabel stage before Prometheus remote write. Logs pass through one static identity stage before Loki write.

```text
host + cAdvisor + Beyla + database exporters
                    |
             identity labels
                    |
          Prometheus remote_write

Docker discovery/logs + NGINX files
                    |
             identity labels
                    |
                 Loki
```

The live modular configuration is `/etc/alloy/per-host-observe/*.alloy`. Secrets are held in `/etc/per-host-observe/agent.env` and injected by a systemd drop-in; generated Alloy files refer to `sys.env` and do not contain credentials. State remains in `/var/lib/alloy`.

On the central VPS, outputs may connect directly to loopback Prometheus and Loki listeners. The renderer omits `basic_auth` blocks when `OBSERVABILITY_AUTH_ENABLED=false`; validation restricts that mode to loopback ingestion URLs.

No Grafana, Prometheus, Loki, NGINX, database, standalone exporter, tracing, profiling, or Kubernetes service is deployed.
