# Troubleshooting

Start with:

```sh
sudo sh status.sh
sudo journalctl -u alloy -n 200 --no-pager
sudo sh check-configs.sh
```

- **Docker socket permission denied:** confirm `id alloy` includes `docker`, then restart Alloy. Remember this group is root-equivalent.
- **NGINX log permission denied:** inspect `getfacl /var/log/nginx /var/log/nginx/access.log` and rerun `start.sh` to restore narrowly scoped ACLs.
- **Beyla capability missing:** inspect `getcap "$(command -v alloy)"` and `systemctl cat alloy`. Confirm kernel/provider eBPF support. Disable with `ENABLE_BEYLA=false` if instrumentation is intentionally unavailable.
- **Prometheus or Loki 401/403:** rotate or correct the per-host Basic Auth username/password.
- **Prometheus or Loki 404:** correct the configured ingress path.
- **Central VPS loopback connection refused:** confirm the service listener and port with `ss -lnt`, and confirm Prometheus's remote-write receiver is enabled. Default examples assume Prometheus `127.0.0.1:9090` and Loki `127.0.0.1:3100`.
- **TLS verification failure:** fix DNS, certificate chain, host time, or CA trust. Do not disable verification.
- **Database connection refused:** expose the container port on a unique `127.0.0.1` host port and check the DSN/address. Alloy does not restart databases.
- **Alloy validate failure:** run `sudo alloy validate /etc/alloy/per-host-observe` and compare the reported component with the generated source comment.
- **Unhealthy component:** open the local UI through an SSH tunnel or inspect the journal; never expose port 12345 publicly.

An empty authenticated POST used by preflight can return HTTP 400; this indicates that TLS, routing, and authentication likely succeeded while the intentionally empty protocol payload was rejected.
