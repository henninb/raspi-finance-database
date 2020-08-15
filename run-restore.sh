#!/bin/sh

if [ $# -ne 1 ] && [ $# -ne 2 ]; then
  echo "Usage: $0 <restore-tar-file> [port]"
  exit 1
fi

date=$(date '+%Y-%m-%d')
restore_filename=$1
port=5432

if [ -n "$2" ]; then
  port=$2
fi
echo "port is set to '$port'."

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

echo postgresql database password
if psql -h "${HOST_IP}" -p "${port}" -d postgres -U henninb < finance_db-drop.sql; then
  echo postgresql database password
  pg_restore -h "${HOST_IP}" -p "${port}" -U henninb -F t -d finance_db --verbose "${restore_filename}" | tee -a "finance-db-restore-${date}.log"
else
  echo "failed to drop the old database [finance_db]."
fi

exit 0
