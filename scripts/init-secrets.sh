#!/usr/bin/env bash
# Generates the database and Grafana passwords once. The files are ignored by Git.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p secrets
for name in db_password grafana_admin_password; do
  if [ ! -s "secrets/$name.txt" ]; then
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "secrets/$name.txt"
    echo "Generated secrets/$name.txt"
  fi
done
