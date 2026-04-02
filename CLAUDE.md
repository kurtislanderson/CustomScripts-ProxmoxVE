# CustomScripts-ProxmoxVE

Personal Proxmox VE scripts repo that mirrors [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) conventions exactly. Each script creates an LXC container (or VM) and installs an app natively — no Docker-in-LXC.

## What This Repo Does

Contains `ct/<app>.sh` and `install/<app>-install.sh` script pairs that work identically to community-scripts. The CT script sources community-scripts' framework remotely via curl, so we get the full whiptail wizard, storage selection, networking, and update mechanism for free.

## Critical Conventions

### Always Research Community-Scripts First

Before writing any new script, find the most similar app in [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) and use it as a reference. The goal is to match their patterns exactly.

**Reference scripts by tech stack:**
- **Python/FastAPI + Node frontend + uv:** Mealie (`ct/mealie.sh`, `install/mealie-install.sh`) — closest match for apps like homebox-companion
- **Python/Django + Celery + uv:** Paperless-ngx (`ct/paperless-ngx.sh`, `install/paperless-ngx-install.sh`)
- **Python + Node + pnpm:** AdventureLog (`ct/adventurelog.sh`, `install/adventurelog-install.sh`)
- **Node.js only:** Actual Budget (`ct/actual-budget.sh`, `install/actual-budget-install.sh`)
- **Go binary:** Homebox (`ct/homebox.sh`, `install/homebox-install.sh`)
- **Next.js + PostgreSQL:** Linkwarden (`ct/linkwarden.sh`, `install/linkwarden-install.sh`)

Always fetch and read the actual community-scripts source for the reference app before writing. Patterns evolve — don't rely on memory.

### Native Install, Not Docker-in-LXC

Running Docker inside an LXC just to run one container is wasteful. Install apps natively using the same approach community-scripts uses (uv for Python, npm/yarn for Node, systemd for services). Only use Docker-in-LXC for apps that are genuinely multi-container orchestrations (like Portainer/Dockge which manage other containers).

### Two-File Pattern

Every app needs exactly two files:

```
ct/<app-name>.sh              # Runs on Proxmox host — creates LXC
install/<app-name>-install.sh # Runs inside LXC — installs the app
```

### CT Script Structure (exact ordering matters)

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright / Author / License / Source comments

APP="App Name"
var_tags="${var_tags:-tag1,tag2}"    # Override-friendly syntax
var_cpu="${var_cpu:-2}"              # NOT var_cpu="2"
# ... other var_* defaults

header_info "$APP"
variables
color
catch_errors

function update_script() { ... }

start
build_container
description

# Completion output
```

### Install Script Structure (exact ordering matters)

```bash
#!/usr/bin/env bash

# Copyright / Author / License / Source comments

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"   # Injected by build framework
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ... install steps ...

motd_ssh
customize
cleanup_lxc
```

### Key Conventions

- **`$STD` wrapper:** ALL commands inside `msg_info`/`msg_ok` blocks must be wrapped in `$STD` (suppresses output in non-verbose mode). This includes `apt-get`, `npm`, `uv sync`, `cp`, `mv`, `chmod`, `systemctl`, etc.
- **`msg_info`/`msg_ok` pairs:** Every logical step gets a pair. Shows spinner during work, checkmark on completion.
- **Self-managing helpers:** `setup_uv`, `setup_nodejs`, `setup_postgresql`, `fetch_and_deploy_gh_release`, `check_for_gh_release` handle their own `msg_info`/`msg_ok` output. Do NOT wrap them.
- **Override-friendly defaults:** Use `var_cpu="${var_cpu:-2}"` not `var_cpu="2"`. `APP` is the only direct assignment.
- **Conditional backups in updates:** Guard with `[[ -d ... ]] &&` or `[[ -f ... ]] &&` — files may not exist on early updates.
- **Regenerate start.sh on update:** Use a heredoc, don't restore from backup. Ensures compatibility with new versions.
- **`CLEAN_INSTALL=1`:** Standard pattern for `fetch_and_deploy_gh_release` in update functions. Backup persistent data BEFORE the wipe.
- **Runtime re-setup in updates:** Call `setup_uv`/`setup_nodejs` in `update_script()` before rebuilding to ensure tools are current.
- **Restore `data/` correctly:** `rm -rf /opt/app/data && mv backup /opt/app/data` — don't `mv` onto an existing directory (causes nesting).

### Common Helper Functions

| Function | Usage |
|----------|-------|
| `PYTHON_VERSION="3.12" setup_uv` | Install uv + Python |
| `NODE_VERSION="22" setup_nodejs` | Install Node.js via NodeSource |
| `NODE_MODULE="yarn" NODE_VERSION="24" setup_nodejs` | Node + global yarn |
| `PG_VERSION="16" setup_postgresql` | Install PostgreSQL |
| `PG_DB_NAME="mydb" PG_DB_USER="myuser" setup_postgresql_db` | Create database |
| `fetch_and_deploy_gh_release "app" "org/repo" "tarball" "latest" "/opt/app"` | Download release |
| `check_for_gh_release "app" "org/repo"` | Check for updates (compares `~/.app` version file) |
| `create_self_signed_cert` | Generate TLS cert |

## Research Process for New Apps

1. **Understand the app:** Read the README, Dockerfile, docker-compose.yml, requirements.txt/pyproject.toml, package.json. Understand the tech stack, ports, config model, data persistence.
2. **Find the closest community-scripts reference:** Match by tech stack (see list above). Fetch and read their actual CT + install scripts.
3. **Understand the config model:** Does the app use env vars, config files, or a UI? Are env vars always read or just for bootstrap? What data persists and where? This affects backup/restore in the update function.
4. **Check for external dependencies:** Does the app need a database (PostgreSQL, Redis)? An external service (like our litellm proxy)? These affect prerequisites and the install script.
5. **Design the update function carefully:** What must be backed up before `CLEAN_INSTALL=1`? What gets restored? What gets regenerated? This is where most bugs hide.

## Infrastructure Context

- **LiteLLM proxy** runs as a separate service. Apps that need LLM access connect to it via `HBC_LLM_API_BASE` (or equivalent env var). We do NOT install litellm locally in each app's LXC.
- **Homebox** runs in its own LXC (community-scripts standard install). Homebox Companion connects to it via `HBC_HOMEBOX_URL`.

## Existing Scripts

| App | CT Script | Install Script | Reference Pattern |
|-----|-----------|---------------|-------------------|
| Homebox Companion | `ct/homebox-companion.sh` | `install/homebox-companion-install.sh` | Mealie (Python/FastAPI + SvelteKit + uv) |

## Design Specs and Plans

- Specs: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/`

When adding a new app, create a design spec first (brainstorming skill), then an implementation plan (writing-plans skill), then implement. This ensures the config model, update behavior, and data persistence are thought through before writing code.
