# Security

Use a unique central Basic Auth credential per VPS and rotate it if that host is compromised. Local secrets are Git-ignored and deployed as `root:alloy` mode `0640` in `/etc/per-host-observe/agent.env`.

The central VPS may set `OBSERVABILITY_AUTH_ENABLED=false` for direct loopback ingestion. This exception is rejected unless both Prometheus and Loki URLs use `127.0.0.1` or `localhost`. Plain HTTP is likewise rejected for every non-loopback URL.

Disabling TLS certificate verification is restricted to configurations where every central URL is loopback. Prefer `TLS_INSECURE_SKIP_VERIFY=false` for HTTP endpoints and trusted local HTTPS certificates.

## Docker

The `alloy` account joins the `docker` group when a Docker collector is enabled. Docker socket access is effectively root-equivalent. This is an explicit v1 tradeoff and must be included in host risk reviews.

## Beyla and eBPF

Alloy remains non-root. For metrics-only process/network instrumentation, the installer assigns inheritable file and systemd capabilities: `BPF`, `NET_ADMIN`, `NET_RAW`, `PERFMON`, `DAC_READ_SEARCH`, `SYS_PTRACE`, and `CHECKPOINT_RESTORE`; `SYS_RESOURCE` is added on kernels older than 5.11. `SYS_ADMIN` is omitted because library-level instrumentation is not enabled. The same set is restricted with `CapabilityBoundingSet`. Remove it by disabling Beyla and rerunning `start.sh`, or run `scripts/uninstall.sh`.

Capability support depends on the host kernel, libcap, seccomp, LSM, and provider policy. Installation fails rather than switching Alloy to root. Review the [current Alloy Beyla permissions reference](https://grafana.com/docs/alloy/latest/reference/components/beyla/beyla.ebpf/) before changing this set.

## Files and databases

NGINX access uses per-user ACLs, including a default directory ACL so rotated files remain readable. Logs are never made world-readable. Database exporters must use dedicated monitoring users, not application superusers. Host-published database ports must bind to `127.0.0.1`.

Keep `.env`, `instances/*/*.env`, and `/etc/per-host-observe` protected. The Alloy interface must remain on `127.0.0.1:12345`.
