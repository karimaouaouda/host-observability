# Configuration

Copy `.env.example` to `.env` and change at least `HOST_ID`, `OBSERVABILITY_USERNAME`, and `OBSERVABILITY_PASSWORD`. The host ID must be stable and unique. TLS verification cannot be disabled by this project, and the Alloy listener must use loopback.

## Central VPS loopback mode

If Alloy runs on the same VPS as the central stack, start from `examples/central-vps.example.env`. Typical direct endpoints are:

```dotenv
GRAFANA_URL=http://127.0.0.1:3000
PROMETHEUS_WRITE_URL=http://127.0.0.1:9090/api/v1/write
LOKI_WRITE_URL=http://127.0.0.1:3100/loki/api/v1/push
OBSERVABILITY_AUTH_ENABLED=false
OBSERVABILITY_USERNAME=
OBSERVABILITY_PASSWORD=
```

Confirm the ports and paths against the central stack. Prometheus must have its remote-write receiver enabled. The validator permits plain HTTP only for `127.0.0.1` or `localhost`, and permits disabled Basic Auth only when both ingestion endpoints are loopback URLs. This exception never permits unencrypted remote transport.

Collectors are controlled with explicit `true` or `false` values. Beyla port discovery must be bounded to application ports. `1-65535` is rejected.

Configuration files use literal `KEY=value` records. They are not shell scripts: quoting has no special meaning, variables are not expanded, and commands are never evaluated. Do not surround a value with quotes unless the quote characters are intended to be part of the value.

Validate without changing the host:

```sh
sudo sh check-configs.sh
```

The renderer creates deterministic files in a staging directory. Users should edit only `.env` and `instances/*/*.env`, never generated or live Alloy files.
