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
