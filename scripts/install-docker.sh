#!/usr/bin/env bash
# Installs Docker Engine and the Compose plugin from Ubuntu's own repositories.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2
systemctl enable --now docker
usermod -aG docker vagrant
