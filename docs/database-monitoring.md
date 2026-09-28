# Database monitoring

Create one instance file for each independently reachable database server:

```sh
cp examples/postgres.example.env instances/postgres/app.env
cp examples/mysql.example.env instances/mysql/shop.env
cp examples/redis.example.env instances/redis/cache.env
```

PostgreSQL `AUTODISCOVERY=true` lets one embedded exporter discover all logical databases on that server. MySQL DSNs use Go MySQL driver syntax such as `user:password@(127.0.0.1:13306)/`, not PostgreSQL URL syntax. Redis key scans and per-key metrics are not enabled.

Use dedicated least-privilege monitoring accounts. For Dockerized databases, publish only a loopback port:

```yaml
ports:
  - "127.0.0.1:15432:5432"
```

Choose a different host port for every instance. Never use ephemeral container IPs or bind monitoring database ports to `0.0.0.0`. The scripts report connectivity problems but never edit Compose files or restart a database.
