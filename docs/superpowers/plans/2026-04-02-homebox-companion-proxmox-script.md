# Homebox Companion Proxmox Script — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a community-scripts-style Proxmox installation script for homebox-companion with a comprehensive README for the repo.

**Architecture:** Three files — a CT script that sources community-scripts' `build.func` and creates an LXC container, an install script that runs inside the container to natively install homebox-companion (Python 3.12 + Node.js 22 + uv), and a README documenting usage and how to add new apps.

**Tech Stack:** Bash (shell scripts), community-scripts ProxmoxVE framework (`build.func`, `install.func`, `tools.func`)

**Spec:** `docs/superpowers/specs/2026-04-02-homebox-companion-proxmox-script-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ct/homebox-companion.sh` | LXC creation + update function (runs on Proxmox host) |
| Create | `install/homebox-companion-install.sh` | App installation inside LXC container |
| Create | `README.md` | Repo overview, usage guide, how-to-add-new-apps template |

---

### Task 1: Create the CT Script

**Files:**
- Create: `ct/homebox-companion.sh`

- [ ] **Step 1: Create the `ct/` directory**

```bash
mkdir -p ct
```

- [ ] **Step 2: Write `ct/homebox-companion.sh`**

Create `ct/homebox-companion.sh` with this exact content:

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Kurt Anderson
# Author: Kurt Anderson
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Duelion/homebox-companion

# App Default Values
APP="Homebox Companion"
var_tags="${var_tags:-inventory,ai}"
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

  if [[ ! -d /opt/homebox-companion ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "homebox-companion" "Duelion/homebox-companion"; then
    # Ensure runtimes are current before rebuilding
    PYTHON_VERSION="3.12" setup_uv
    NODE_VERSION="22" setup_nodejs

    msg_info "Stopping Service"
    $STD systemctl stop homebox-companion
    msg_ok "Stopped Service"

    # Backup persistent data and config (conditional — may not exist on early update)
    msg_info "Backing up data and configuration"
    [[ -d /opt/homebox-companion/data ]] && $STD cp -r /opt/homebox-companion/data /opt/homebox-companion-data-backup
    [[ -f /opt/homebox-companion/.env ]] && $STD cp -f /opt/homebox-companion/.env /opt/homebox-companion.env.backup
    msg_ok "Backup complete"

    # Fetch and deploy new release (CLEAN_INSTALL wipes target dir — data already backed up above)
    # fetch_and_deploy_gh_release manages its own msg_info/msg_ok output
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "homebox-companion" "Duelion/homebox-companion" "tarball" "latest" "/opt/homebox-companion"

    # Rebuild frontend
    msg_info "Building Frontend"
    cd /opt/homebox-companion/frontend
    $STD npm ci
    $STD npm run build
    $STD cp -r /opt/homebox-companion/frontend/build/* /opt/homebox-companion/server/static/
    msg_ok "Built Frontend"

    # Reinstall Python deps
    msg_info "Installing Python Dependencies"
    cd /opt/homebox-companion
    $STD uv sync --no-dev
    msg_ok "Installed Python Dependencies"

    # Restore persistent data and config (only what was backed up)
    msg_info "Restoring data and configuration"
    if [[ -d /opt/homebox-companion-data-backup ]]; then
      rm -rf /opt/homebox-companion/data
      $STD mv /opt/homebox-companion-data-backup /opt/homebox-companion/data
    fi
    mkdir -p /opt/homebox-companion/data
    [[ -f /opt/homebox-companion.env.backup ]] && $STD mv -f /opt/homebox-companion.env.backup /opt/homebox-companion/.env
    msg_ok "Restored data and configuration"

    # Regenerate start script (ensures it matches current version)
    msg_info "Creating Start Script"
    cat <<'EOF' >/opt/homebox-companion/start.sh
#!/bin/bash
set -a
source /opt/homebox-companion/.env
set +a
cd /opt/homebox-companion
exec uv run python -m server.app
EOF
    $STD chmod +x /opt/homebox-companion/start.sh
    msg_ok "Created Start Script"

    msg_info "Starting Service"
    $STD systemctl start homebox-companion
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x ct/homebox-companion.sh
```

- [ ] **Step 4: Verify with shellcheck (syntax only — can't run without Proxmox)**

```bash
shellcheck ct/homebox-companion.sh || echo "Note: shellcheck warnings about sourced functions are expected since build.func is loaded at runtime"
```

Expected: warnings about undefined variables from the sourced framework (SC2154, SC2034) are expected and harmless.

- [ ] **Step 5: Commit**

```bash
git add ct/homebox-companion.sh
git commit -m "feat: add homebox-companion CT script for LXC creation"
```

---

### Task 2: Create the Install Script

**Files:**
- Create: `install/homebox-companion-install.sh`

- [ ] **Step 1: Create the `install/` directory**

```bash
mkdir -p install
```

- [ ] **Step 2: Write `install/homebox-companion-install.sh`**

Create `install/homebox-companion-install.sh` with this exact content:

```bash
#!/usr/bin/env bash

# Copyright (c) 2026 Kurt Anderson
# Author: Kurt Anderson
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Duelion/homebox-companion

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "homebox-companion" "Duelion/homebox-companion" "tarball" "latest" "/opt/homebox-companion"

msg_info "Building Frontend"
cd /opt/homebox-companion/frontend
$STD npm ci
$STD npm run build
$STD cp -r /opt/homebox-companion/frontend/build/* /opt/homebox-companion/server/static/
msg_ok "Built Frontend"

msg_info "Installing Python Dependencies"
cd /opt/homebox-companion
$STD uv sync --no-dev
msg_ok "Installed Python Dependencies"

msg_info "Setting Up Data Directory"
$STD mkdir -p /opt/homebox-companion/data
msg_ok "Set Up Data Directory"

msg_info "Writing Environment File"
cat <<'EOF' >/opt/homebox-companion/.env
# Homebox Companion Configuration
#
# ALWAYS ENV-DRIVEN (read on every startup):
HBC_HOMEBOX_URL=
HBC_SERVER_HOST=0.0.0.0
HBC_SERVER_PORT=8000
HBC_LOG_LEVEL=INFO
HBC_CORS_ORIGINS=*

# BOOTSTRAP ONLY (seed data/settings.yaml on first boot, then use Settings UI):
HBC_LLM_API_BASE=
HBC_LLM_API_KEY=
HBC_LLM_MODEL=gpt-5-mini
EOF
msg_ok "Wrote Environment File"

msg_info "Creating Start Script"
cat <<'EOF' >/opt/homebox-companion/start.sh
#!/bin/bash
set -a
source /opt/homebox-companion/.env
set +a
cd /opt/homebox-companion
exec uv run python -m server.app
EOF
$STD chmod +x /opt/homebox-companion/start.sh
msg_ok "Created Start Script"

msg_info "Creating Systemd Service"
cat <<'EOF' >/etc/systemd/system/homebox-companion.service
[Unit]
Description=Homebox Companion
After=network.target

[Service]
Type=simple
ExecStart=/opt/homebox-companion/start.sh
WorkingDirectory=/opt/homebox-companion
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
$STD systemctl daemon-reload
$STD systemctl enable -q --now homebox-companion
msg_ok "Created and Started Service"

motd_ssh
customize
cleanup_lxc
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x install/homebox-companion-install.sh
```

- [ ] **Step 4: Verify with shellcheck**

```bash
shellcheck install/homebox-companion-install.sh || echo "Note: shellcheck warnings about sourced functions are expected since install.func is loaded at runtime"
```

Expected: warnings about undefined variables/functions from the sourced framework are expected.

- [ ] **Step 5: Commit**

```bash
git add install/homebox-companion-install.sh
git commit -m "feat: add homebox-companion install script for LXC container setup"
```

---

### Task 3: Create the README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

Create `README.md` with this content:

````markdown
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
bash -c "$(wget -qLO - https://raw.githubusercontent.com/<your-user>/CustomScripts-ProxmoxVE/main/ct/homebox-companion.sh)"
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
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage guide and new-app template"
```

---

### Task 4: Final Verification and Commit

- [ ] **Step 1: Verify repo structure**

```bash
find ct install README.md -type f | sort
```

Expected output:
```
README.md
ct/homebox-companion.sh
install/homebox-companion-install.sh
```

- [ ] **Step 2: Verify scripts are executable**

```bash
ls -la ct/homebox-companion.sh install/homebox-companion-install.sh
```

Expected: both show `-rwxr-xr-x` permissions.

- [ ] **Step 3: Verify shellcheck passes (informational)**

```bash
shellcheck ct/homebox-companion.sh install/homebox-companion-install.sh 2>&1 | head -20
```

Expected: only SC2154 (referenced but not assigned) and SC2034 (appears unused) warnings from the sourced framework variables. No syntax errors.

- [ ] **Step 4: Verify no secrets are present**

```bash
grep -rn 'sk-\|api_key\|password\|secret' ct/ install/ README.md | grep -v 'example\|placeholder\|your-\|template\|comment'
```

Expected: no output (no real secrets in any file).

---

### Task 5: Runtime Acceptance Tests (requires live Proxmox)

These tests must be run on a real Proxmox host with a running Homebox instance and LiteLLM proxy.

- [ ] **Step 1: Run CT script — verify LXC creation**

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/<your-user>/CustomScripts-ProxmoxVE/main/ct/homebox-companion.sh)"
```

Expected: community-scripts wizard launches, LXC container created with 2 CPU, 1024 MB RAM, 4 GB disk, Debian 13.

- [ ] **Step 2: Verify install completed without errors**

SSH into the container and check:

```bash
systemctl status homebox-companion
```

Expected: `active (running)`.

- [ ] **Step 3: Verify web UI loads**

```bash
curl -s -o /dev/null -w "%{http_code}" http://<container-ip>:8000
```

Expected: `200`.

- [ ] **Step 4: Configure `.env` and verify first boot**

```bash
nano /opt/homebox-companion/.env
# Fill in HBC_HOMEBOX_URL, HBC_LLM_API_BASE, HBC_LLM_API_KEY
systemctl restart homebox-companion
```

After restart, verify `data/settings.yaml` was created:

```bash
ls -la /opt/homebox-companion/data/settings.yaml
```

Expected: file exists with LLM profile seeded from `.env` values.

- [ ] **Step 5: Verify Settings UI persists changes**

Open `http://<container-ip>:8000/settings` in a browser. Change an LLM setting. Verify it persists in `data/settings.yaml`:

```bash
cat /opt/homebox-companion/data/settings.yaml
```

Expected: the changed value appears in the YAML file.

- [ ] **Step 6: Run update — verify data survives**

Re-run the CT script and select update. After update completes:

```bash
ls -la /opt/homebox-companion/data/settings.yaml
cat /opt/homebox-companion/data/settings.yaml
```

Expected: `data/settings.yaml` still exists with the settings from Step 5 intact.

- [ ] **Step 7: Test update on fresh install (before first boot)**

Create a new LXC with the CT script. Before configuring `.env` or starting the service for the first time, re-run the CT script and select update.

Expected: update completes without errors. No crash from missing `data/` directory. The conditional backup guards handle the missing files gracefully.
