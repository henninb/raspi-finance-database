#!/bin/sh

if [ $# -ne 0 ]; then
  echo "Usage: $0 <noargs>"
  exit 1
fi

date=$(date '+%Y-%m-%d')

cat aaaa_tables.sql zzzz_tables.sql > master.sql

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

echo postgresql database password
psql -h "${HOST_IP}" -p 5432 -d postgres -U henninb < master.sql | tee -a "finance-db-install-${date}.log"

echo psql finance_db -U henninb -h "${HOST_IP}" -p 5432

exit 0
