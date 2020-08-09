#!/bin/sh

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

echo postgresql database password
psql -h "${HOST_IP}" -d postgres -U henninb < finance_db-drop.sql
echo postgresql database password
pg_restore -h "${HOST_IP}" -p 5432 -U henninb -F t -d finance_db --verbose finance_db.tar

exit 0
