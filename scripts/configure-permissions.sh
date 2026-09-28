#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=${PROJECT_ROOT:-$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)}
. "$SCRIPT_DIR/common.sh"
require_root

parsed=$(mktemp)
trap 'rm -f "$parsed"' EXIT HUP INT TERM
config_parse "$PROJECT_ROOT/.env" "$GLOBAL_KEYS" "$parsed"

getent passwd alloy >/dev/null || die 'The alloy service account does not exist; install Alloy first.'
install -d -o root -g alloy -m 0750 /etc/per-host-observe /etc/alloy
install -d -o alloy -g alloy -m 0750 /var/lib/alloy
install -d -o root -g root -m 0750 /var/lib/per-host-observe/backups
install -d -o root -g root -m 0755 /etc/systemd/system/alloy.service.d

if is_true "$(config_get "$parsed" ENABLE_DOCKER_METRICS)" || is_true "$(config_get "$parsed" ENABLE_DOCKER_LOGS)"; then
    getent group docker >/dev/null || die 'Docker group is missing; verify the Docker Engine installation.'
    if ! id -nG alloy | tr ' ' '\n' | grep -Fx docker >/dev/null; then
        usermod -aG docker alloy
        : >/var/lib/per-host-observe/added-docker-group
        warn 'The alloy user was added to docker; Docker group membership is effectively root-equivalent.'
    else
        info 'The alloy user already belongs to the docker group.'
    fi
elif [ -f /var/lib/per-host-observe/added-docker-group ]; then
    gpasswd -d alloy docker >/dev/null 2>&1 || true
    rm -f /var/lib/per-host-observe/added-docker-group
    info 'Removed the project-managed Docker group membership because Docker collection is disabled.'
fi

if is_true "$(config_get "$parsed" ENABLE_NGINX_LOGS)"; then
    for key in NGINX_ACCESS_LOG NGINX_ERROR_LOG; do
        log_path=$(config_get "$parsed" "$key")
        log_dir=$(dirname "$log_path")
        if [ -d "$log_dir" ]; then
            setfacl -m u:alloy:rx "$log_dir"
            setfacl -m d:u:alloy:r-X "$log_dir"
            [ ! -e "$log_path" ] || setfacl -m u:alloy:r "$log_path"
            printf '%s\n' "$log_path" >>/var/lib/per-host-observe/nginx-acl-paths
        else
            warn "NGINX log directory does not exist yet: $log_dir"
        fi
    done
elif [ -f /var/lib/per-host-observe/nginx-acl-paths ]; then
    sort -u /var/lib/per-host-observe/nginx-acl-paths | while IFS= read -r log_path; do
        [ -n "$log_path" ] || continue
        log_dir=$(dirname "$log_path")
        setfacl -x u:alloy "$log_path" 2>/dev/null || true
        setfacl -x u:alloy "$log_dir" 2>/dev/null || true
        setfacl -x d:u:alloy "$log_dir" 2>/dev/null || true
    done
    rm -f /var/lib/per-host-observe/nginx-acl-paths
    info 'Removed project-managed NGINX ACLs because NGINX collection is disabled.'
fi

capabilities=''
if is_true "$(config_get "$parsed" ENABLE_BEYLA)"; then
    alloy_binary=$(command -v alloy)
    capabilities='CAP_BPF CAP_NET_ADMIN CAP_NET_RAW CAP_PERFMON CAP_DAC_READ_SEARCH CAP_SYS_PTRACE CAP_CHECKPOINT_RESTORE'
    file_caps='cap_bpf,cap_net_admin,cap_net_raw,cap_perfmon,cap_dac_read_search,cap_sys_ptrace,cap_checkpoint_restore'
    if version_lt_5_11; then
        capabilities="$capabilities CAP_SYS_RESOURCE"
        file_caps="$file_caps,cap_sys_resource"
    fi
    setcap "$file_caps+ip" "$alloy_binary" || die 'Unable to assign the documented non-root Beyla capabilities to Alloy.'
    info "Configured non-root Beyla capabilities: $capabilities"
else
    alloy_binary=$(command -v alloy)
    setcap -r "$alloy_binary" 2>/dev/null || true
fi

cat >/etc/systemd/system/alloy.service.d/per-host-observe.conf <<EOF
[Service]
User=alloy
Group=alloy
EnvironmentFile=/etc/per-host-observe/agent.env
AmbientCapabilities=$capabilities
InheritableCapabilities=$capabilities
CapabilityBoundingSet=$capabilities
NoNewPrivileges=false
EOF
chmod 0644 /etc/systemd/system/alloy.service.d/per-host-observe.conf
systemctl daemon-reload
ok 'Configured Alloy filesystem and service permissions'
