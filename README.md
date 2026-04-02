# CustomScripts-ProxmoxVE

Personal Proxmox VE scripts for creating LXC containers and VMs, following the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) conventions. Each script sources the community-scripts framework remotely — no local framework to maintain.

## Prerequisites

- Proxmox VE 8.x or later
- Internet access from the Proxmox host (scripts fetch the framework and app releases from GitHub)

## Available Scripts

| App | Type | Script | Description |
|-----|------|--------|-------------|
| [Homebox Companion](https://github.com/Duelion/homebox-companion) | LXC | `ct/homebox-companion.sh` | AI-powered companion for Homebox inventory management |

## Usage

### Install a New App

Run from the **Proxmox host shell** (not inside a container):

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/kurtislanderson/CustomScripts-ProxmoxVE/main/ct/homebox-companion.sh)"
```

This launches the community-scripts wizard — configure resources, networking, and storage interactively, then the LXC container is created and the app installed automatically.

### Update an Existing App

Run the same command again. The script detects the existing installation and offers to update it.

---

## Homebox Companion

### What It Does

AI-powered companion for [Homebox](https://github.com/sysadminsmedia/homebox) inventory management. Photograph items and use LLM vision to automatically identify and catalog them.

### Prerequisites

Before installing, you need:

1. **A running Homebox instance** — the companion connects to it via `HBC_HOMEBOX_URL`
2. **A running LiteLLM proxy** — the companion routes LLM requests through your proxy via `HBC_LLM_API_BASE`

### Post-Install Configuration

After the script completes, edit the environment file inside the container:

```bash
nano /opt/homebox-companion/.env
```

Fill in the required values:

```ini
# ALWAYS ENV-DRIVEN (read on every startup):
HBC_HOMEBOX_URL=http://192.168.1.100:7745    # Your Homebox instance
HBC_SERVER_HOST=0.0.0.0
HBC_SERVER_PORT=8000
HBC_LOG_LEVEL=INFO
HBC_CORS_ORIGINS=http://192.168.1.0/24       # Restrict in production (default: * allows all)

# BOOTSTRAP ONLY (seed data/settings.yaml on first boot, then use Settings UI):
HBC_LLM_API_BASE=http://192.168.1.50:4000    # Your LiteLLM proxy
HBC_LLM_API_KEY=sk-your-litellm-key          # Key for your LiteLLM proxy
HBC_LLM_MODEL=gpt-5-mini                     # Model name in your LiteLLM proxy
```

Then restart the service:

```bash
systemctl restart homebox-companion
```

To update later, run the same Proxmox host install command again and choose the update path when the script detects the existing container.

### Configuration Model

Homebox Companion uses a two-layer configuration:

- **Always env-driven:** `HBC_HOMEBOX_URL`, `HBC_SERVER_HOST`, `HBC_SERVER_PORT`, `HBC_LOG_LEVEL`, `HBC_CORS_ORIGINS` — read from `.env` on every startup
- **Bootstrap-only:** `HBC_LLM_API_BASE`, `HBC_LLM_API_KEY`, `HBC_LLM_MODEL` — used on first boot to seed `data/settings.yaml`, then managed via the Settings UI in the web interface

After first boot, manage LLM profiles and field preferences through the Settings UI at `http://<container-ip>:8000/settings`.

### Resources

| Resource | Default |
|----------|---------|
| CPU | 2 cores |
| RAM | 1024 MB |
| Disk | 4 GB |
| OS | Debian 13 (Trixie) |
| Port | 8000 |

### Security

- The LXC container runs **unprivileged** by default (`var_unprivileged=1`)
- **No API keys are stored in scripts** — all secrets are configured in `.env` post-install
- After first boot, LLM secrets (API keys, model config) move into `data/settings.yaml` inside the container — they are never in git-tracked files
- **LiteLLM is managed externally** — the bundled litellm Python library only acts as an HTTP client to your separately managed, version-pinned proxy
- **Restrict CORS in production** — set `HBC_CORS_ORIGINS` in `.env` (defaults to `*` which allows all origins)

---

## Adding a New App

Each app needs two files:

```
ct/<app-name>.sh              # Runs on the Proxmox host — creates the LXC
install/<app-name>-install.sh  # Runs inside the LXC — installs the app
```

### CT Script Template

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Your Name
# Author: Your Name
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/org/app

# App Default Values
APP="App Name"
var_tags="${var_tags:-tag1,tag2}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# App Output & Base Settings
header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/app-name ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "app-name" "org/app"; then
    # Re-setup runtimes if needed
    # PYTHON_VERSION="3.12" setup_uv
    # NODE_VERSION="22" setup_nodejs

    msg_info "Stopping Service"
    $STD systemctl stop app-name
    msg_ok "Stopped Service"

    # Backup config (conditional for safety)
    msg_info "Backing up configuration"
    [[ -f /opt/app-name/.env ]] && $STD cp -f /opt/app-name/.env /opt/app-name.env.backup
    # Add any other persistent data backups here
    msg_ok "Backup complete"

    # Deploy new release
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "app-name" "org/app" "tarball" "latest" "/opt/app-name"

    # Rebuild / reinstall deps as needed
    # ...

    # Restore config
    msg_info "Restoring configuration"
    [[ -f /opt/app-name.env.backup ]] && $STD mv -f /opt/app-name.env.backup /opt/app-name/.env
    msg_ok "Restored configuration"

    msg_info "Starting Service"
    $STD systemctl start app-name
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:<PORT>${CL}"
```

### Install Script Template

```bash
#!/usr/bin/env bash

# Copyright (c) 2026 Your Name
# Author: Your Name
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/org/app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Install system dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git
msg_ok "Installed Dependencies"

# Setup language runtimes (these manage their own output)
# PYTHON_VERSION="3.12" setup_uv
# NODE_VERSION="22" setup_nodejs

# Fetch app source/binary (manages its own output)
# fetch_and_deploy_gh_release "app-name" "org/app" "tarball" "latest" "/opt/app-name"

# Build steps — wrap in $STD and msg_info/msg_ok
# msg_info "Building App"
# $STD npm ci
# $STD npm run build
# msg_ok "Built App"

# Write config files using heredocs
# msg_info "Writing Environment File"
# cat <<'EOF' >/opt/app-name/.env
# KEY=value
# EOF
# msg_ok "Wrote Environment File"

# Create systemd service
# msg_info "Creating Systemd Service"
# cat <<'EOF' >/etc/systemd/system/app-name.service
# [Unit]
# Description=App Name
# After=network.target
# [Service]
# Type=simple
# ExecStart=/opt/app-name/start.sh
# Restart=on-failure
# [Install]
# WantedBy=multi-user.target
# EOF
# systemctl enable -q --now app-name
# msg_ok "Created and Started Service"

motd_ssh
customize
cleanup_lxc
```

### Key Conventions

- **`$STD` wrapper:** All build/install commands must be wrapped in `$STD` (suppresses output in non-verbose mode)
- **`msg_info` / `msg_ok`:** Every logical step gets a pair (shows spinner during work, checkmark on completion)
- **Self-managing helpers:** `setup_uv`, `setup_nodejs`, `fetch_and_deploy_gh_release` handle their own output — do NOT wrap them in `msg_info`/`msg_ok`
- **Override-friendly defaults:** Use `var_cpu="${var_cpu:-2}"` not `var_cpu="2"` (lets the framework override)
- **`APP` is direct assignment:** `APP="Name"` not `APP="${APP:-Name}"`
- **Conditional backups:** In `update_script()`, guard backups with `[[ -d ... ]] &&` or `[[ -f ... ]] &&`
- **Regenerate start.sh on update:** Use a heredoc instead of restoring from backup (ensures compatibility with new version)

### Useful Helper Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `setup_uv` | Install uv + Python | `PYTHON_VERSION="3.12" setup_uv` |
| `setup_nodejs` | Install Node.js | `NODE_VERSION="22" setup_nodejs` |
| `setup_postgresql` | Install PostgreSQL | `PG_VERSION="16" setup_postgresql` |
| `setup_postgresql_db` | Create a database | `PG_DB_NAME="mydb" PG_DB_USER="myuser" setup_postgresql_db` |
| `fetch_and_deploy_gh_release` | Download GitHub release | Modes: `tarball`, `binary`, `prebuild`, `singlefile` |
| `check_for_gh_release` | Check for updates | Compares `~/.app-name` version to GitHub API |
| `create_self_signed_cert` | Generate TLS cert | For HTTPS-required apps |

Full framework docs: [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)

---

## Acknowledgments

- **[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)** — MIT License. This repo sources their framework at runtime for LXC creation, networking, storage selection, and update management.
- **[Homebox Companion](https://github.com/Duelion/homebox-companion)** — GPL v3 License. The install script downloads and installs this application; no source code is bundled or redistributed in this repo.
- **[Homebox](https://github.com/sysadminsmedia/homebox)** — The inventory management system that Homebox Companion connects to.

## License

This project is licensed under the [MIT License](LICENSE).
