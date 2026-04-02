# Homebox Companion Proxmox Script — Design Spec

## Overview

Create a personal Proxmox scripts repository (CustomScripts-ProxmoxVE) mirroring the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) conventions. The first app is [homebox-companion](https://github.com/Duelion/homebox-companion) — an AI-powered companion for Homebox inventory management.

The repo is designed to grow over time with additional app scripts following the same pattern.

## Architecture Decision: Source Community-Scripts Framework Remotely

Rather than forking or building a custom framework, CT scripts source community-scripts' shared `.func` libraries directly from GitHub via curl (using `raw.githubusercontent.com`, which is the canonical URL used internally by community-scripts' own `build.func`). This gives full feature parity (whiptail wizard, storage selection, cluster-aware ID validation, networking, update mechanism) with zero framework maintenance.

## Architecture Decision: Native Install (No Docker)

Homebox-companion runs natively inside the LXC container — no Docker-in-LXC. This eliminates the ~100-150MB Docker daemon overhead and matches how community-scripts handles similar Python+Node apps (e.g., Mealie, Paperless-ngx).

## Architecture Decision: External LiteLLM Proxy

The user runs a separate litellm proxy instance that multiple services share. Homebox-companion connects to it via `HBC_LLM_API_BASE`. The litellm Python library bundled with homebox-companion acts only as an HTTP client to this proxy — no local LLM routing. This addresses the March 2026 litellm supply chain attack concern by centralizing litellm management in a controlled, version-pinned instance.

## Architecture Decision: Config Model — Two-Layer Configuration

Upstream homebox-companion uses two configuration layers (verified in source: `core/config.py` and `core/persistent_settings.py`):

**Layer 1 — Always env-driven (`config.py`, pydantic-settings):**
These settings are read from env vars / `.env` on every startup. They never go into `settings.yaml`:
- `HBC_SERVER_HOST`, `HBC_SERVER_PORT`, `HBC_LOG_LEVEL` (server settings)
- `HBC_HOMEBOX_URL` (Homebox instance URL)
- `HBC_CORS_ORIGINS`, `HBC_MAX_UPLOAD_SIZE_MB`, etc. (operational settings)

**Layer 2 — Bootstrap-then-persist (`persistent_settings.py` → `data/settings.yaml`):**
On first boot, these env vars seed the initial LLM profile in `data/settings.yaml`. After that, the Settings UI manages them and env vars are ignored:
- `HBC_LLM_API_KEY`, `HBC_LLM_API_BASE`, `HBC_LLM_MODEL` → seed the PRIMARY LLM profile
- LLM profiles, field preferences, custom fields → all managed via Settings UI after bootstrap

This means:
- `.env` is always needed for server/operational settings (Layer 1)
- `.env` LLM settings are only used on first boot to seed `data/settings.yaml` (Layer 2)
- `data/` (specifically `data/settings.yaml`) holds LLM profiles and field prefs, must be preserved across updates
- Post-install docs tell the user to configure `.env` for both layers, but after first boot, LLM config moves to the Settings UI

---

## Repo Structure

```
CustomScripts-ProxmoxVE/
├── ct/
│   └── homebox-companion.sh            # LXC creation script (run from Proxmox host)
├── install/
│   └── homebox-companion-install.sh    # App install script (runs inside LXC)
├── README.md                           # Usage guide + how to add new apps
└── docs/
    └── superpowers/specs/              # Design specs
```

To add a new app, create two files: `ct/<app-name>.sh` and `install/<app-name>-install.sh`.

---

## CT Script: `ct/homebox-companion.sh`

### Purpose
Run from the Proxmox host shell. Creates an LXC container with the configured resources, then triggers the install script inside the container.

### Full Script Structure (matching community-scripts conventions)

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

### Default Variables
| Variable | Value | Rationale |
|----------|-------|-----------|
| `APP` | `"Homebox Companion"` | Display name (direct assignment, not overridable) |
| `var_tags` | `"${var_tags:-inventory,ai}"` | Proxmox tags |
| `var_cpu` | `"${var_cpu:-2}"` | Needed for npm build + Python |
| `var_ram` | `"${var_ram:-1024}"` | No Docker overhead |
| `var_disk` | `"${var_disk:-4}"` | Source + deps + built frontend |
| `var_os` | `"${var_os:-debian}"` | Standard community-scripts choice |
| `var_version` | `"${var_version:-13}"` | Debian Trixie (matches community-scripts convention) |
| `var_unprivileged` | `"${var_unprivileged:-1}"` | Security best practice |

### Update Function (`update_script()`)
Follows the standard community-scripts update pattern (see Mealie, AdventureLog, Paperless-ngx):

1. `check_container_storage` and `check_container_resources` — standard pre-flight checks
2. Verify homebox-companion is installed (`/opt/homebox-companion`)
3. `check_for_gh_release` — compare `~/.homebox-companion` version file to GitHub API
4. Re-setup runtimes (`setup_uv`, `setup_nodejs`) — ensures tools are current before rebuild
5. Stop systemd service
6. Conditionally backup `data/` (if it exists) and `.env` (if it exists) — handles early updates before first boot
7. `CLEAN_INSTALL=1 fetch_and_deploy_gh_release` — wipe target dir and deploy new source
8. Rebuild frontend: `$STD npm ci && $STD npm run build`, copy to `server/static/`
9. Re-install Python deps: `$STD uv sync --no-dev`
10. Restore `data/` (rm existing → mv backup into place) and `.env` (only what was backed up); ensure `data/` exists unconditionally via `mkdir -p`
11. Regenerate `start.sh` from heredoc (ensures it matches current version, rather than restoring a stale backup)
12. Restart service

### Post-Install Output
Displays: `http://{container-ip}:8000`

---

## Install Script: `install/homebox-companion-install.sh`

### Purpose
Runs inside the LXC container after creation. Installs all dependencies, builds the app, and configures it as a systemd service.

### Full Script Structure

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

### Install Steps Summary

| Step | Commands | Pattern |
|------|----------|---------|
| System deps | `$STD apt-get install -y curl git` | `msg_info`/`msg_ok` wrapped |
| Python runtime | `PYTHON_VERSION="3.12" setup_uv` | Helper handles its own output |
| Node runtime | `NODE_VERSION="22" setup_nodejs` | Helper handles its own output |
| Fetch source | `fetch_and_deploy_gh_release ...` | Helper handles its own output |
| Build frontend | `$STD npm ci`, `$STD npm run build`, `cp -r` | `msg_info`/`msg_ok` wrapped |
| Python deps | `$STD uv sync --no-dev` | `msg_info`/`msg_ok` wrapped |
| Data directory | `mkdir -p .../data` | `msg_info`/`msg_ok` wrapped |
| Environment file | heredoc → `.env` | `msg_info`/`msg_ok` wrapped |
| Start script | heredoc → `start.sh`, `chmod +x` | `msg_info`/`msg_ok` wrapped |
| Systemd service | heredoc → `.service`, `systemctl enable -q --now` | `msg_info`/`msg_ok` wrapped |
| Standard tail | `motd_ssh`, `customize`, `cleanup_lxc` | Community-scripts convention |

---

## README.md

The README covers:

1. **What this repo is** — Personal Proxmox scripts repo mirroring community-scripts conventions
2. **Prerequisites** — Proxmox VE 8.x+, internet access from host
3. **How to run a script** — One-liner curl command from Proxmox host shell
4. **Homebox Companion specifics:**
   - Prerequisites: running Homebox instance + litellm proxy
   - Post-install: edit `.env` with Homebox URL (always env-driven), LiteLLM proxy URL + API key (bootstrap-only), then restart the service
   - After first boot: server/operational settings stay in `.env`; LLM profiles and field preferences move to the Settings UI (`data/settings.yaml` is the source of truth for those)
   - How to update (re-run the script, select update)
5. **How to add a new app** — Step-by-step guide:
   - CT script template with full boilerplate (shebang, source, metadata, override-friendly `var_*` defaults, `header_info`, `variables`, `color`, `catch_errors`, `update_script`, `start`, `build_container`, `description`)
   - Install script template with standard preamble (`source /dev/stdin`, `color`, `verb_ip6`, `catch_errors`, `setting_up_container`, `network_check`, `update_os`) and tail (`motd_ssh`, `customize`, `cleanup_lxc`)
   - Convention: wrap all build commands in `$STD`, wrap all logical steps in `msg_info`/`msg_ok` pairs
   - Update function template showing conditional backup/restore and runtime re-setup patterns
   - Common helper functions reference (`setup_uv`, `setup_nodejs`, `fetch_and_deploy_gh_release`, etc.)
   - Link to community-scripts docs for full framework reference

---

## Security Considerations

- LXC runs unprivileged (`var_unprivileged="1"`)
- LiteLLM is managed externally — version-pinned, centrally controlled
- The bundled litellm library only acts as an HTTP client to the user's proxy
- No API keys stored in scripts — user configures `.env` for first-boot bootstrap
- After first boot, secrets live in `data/settings.yaml` inside the LXC (not in scripts or env files checked into git)
- CORS should be restricted in production via `HBC_CORS_ORIGINS` in `.env`

## Testing Plan

1. Run CT script on a Proxmox host — verify LXC creation with correct resources
2. Verify install completes without errors
3. Verify `systemctl status homebox-companion` shows active
4. Verify `http://<container-ip>:8000` loads the web UI
5. Configure `.env` with real Homebox URL + litellm proxy, restart service, verify first-boot config seeds `data/settings.yaml`
6. Verify Settings UI can modify config and changes persist in `data/settings.yaml`
7. Run update function — verify `data/` directory is preserved, settings survive the upgrade
8. Run update on a fresh install (before first boot) — verify conditional backup handles missing `data/` gracefully
