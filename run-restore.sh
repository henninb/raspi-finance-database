#!/bin/sh

if [ $# -ne 0 ]; then
  echo "Usage: $0 <noargs>"
  exit 1
fi

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

port=5432

echo postgresql database password
psql -h "${HOST_IP}" -p ${port} -d postgres -U henninb < finance_db-drop.sql
echo postgresql database password
pg_restore -h "${HOST_IP}" -p ${port} -U henninb -F t -d finance_db --verbose finance_db.tar

exit 0
