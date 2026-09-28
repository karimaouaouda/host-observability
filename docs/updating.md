# Updating

Project updates are idempotent:

```sh
git pull
sudo sh check-configs.sh
sudo sh start.sh
```

`start.sh` does not upgrade an existing Alloy package. Upgrade deliberately:

```sh
sudo sh scripts/upgrade-alloy.sh
```

Every deployment validates before replacing the live directory, snapshots the current configuration under `/var/lib/per-host-observe/backups`, and restores it automatically if restart/readiness/health verification fails. Failed candidates are retained for diagnosis.

`stop.sh` stops only Alloy. `scripts/uninstall.sh` removes project-owned configuration and permissions after confirmation, while preserving the Alloy package, telemetry state, and rollback backups.
