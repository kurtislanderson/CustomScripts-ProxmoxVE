#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Patch build_container to fetch install script from this repo instead of community-scripts
eval "$(declare -f build_container | sed 's|https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}|https://raw.githubusercontent.com/kurtislanderson/CustomScripts-ProxmoxVE/main/install/${var_install}|g')"

# Copyright (c) 2026 Kurt Anderson
# Author: Kurt Anderson
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Duelion/homebox-companion

# App Default Values
APP="Homebox Companion"
var_tags="${var_tags:-inventory,ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
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
    systemctl stop homebox-companion
    msg_ok "Stopped Service"

    # Backup persistent data and config (conditional — may not exist on early update)
    msg_info "Backing up data and configuration"
    [[ -d /opt/homebox-companion/data ]] && cp -r /opt/homebox-companion/data /opt/homebox-companion-data-backup
    [[ -f /opt/homebox-companion/.env ]] && cp -f /opt/homebox-companion/.env /opt/homebox-companion.env.backup
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
      mv /opt/homebox-companion-data-backup /opt/homebox-companion/data
    fi
    mkdir -p /opt/homebox-companion/data
    [[ -f /opt/homebox-companion.env.backup ]] && mv -f /opt/homebox-companion.env.backup /opt/homebox-companion/.env
    msg_ok "Restored data and configuration"

    # Regenerate start script (ensures it matches current version)
    msg_info "Creating Start Script"
    cat <<'EOF' >/opt/homebox-companion/start.sh
#!/bin/bash
set -a
source /opt/homebox-companion/.env
set +a
cd /opt/homebox-companion
exec /usr/local/bin/uv run python -m server.app
EOF
    chmod +x /opt/homebox-companion/start.sh
    msg_ok "Created Start Script"

    msg_info "Starting Service"
    systemctl start homebox-companion
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
