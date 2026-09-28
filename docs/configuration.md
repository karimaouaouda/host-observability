# Configuration

Copy `.env.example` to `.env` and change at least `HOST_ID`, `OBSERVABILITY_USERNAME`, and `OBSERVABILITY_PASSWORD`. The host ID must be stable and unique. TLS verification cannot be disabled by this project, and the Alloy listener must use loopback.

Collectors are controlled with explicit `true` or `false` values. Beyla port discovery must be bounded to application ports. `1-65535` is rejected.

Configuration files use literal `KEY=value` records. They are not shell scripts: quoting has no special meaning, variables are not expanded, and commands are never evaluated. Do not surround a value with quotes unless the quote characters are intended to be part of the value.

Validate without changing the host:

```sh
sudo sh check-configs.sh
```

The renderer creates deterministic files in a staging directory. Users should edit only `.env` and `instances/*/*.env`, never generated or live Alloy files.
