#!/bin/sh

cat aaaa_tables.sql zzzz_tables.sql > master.sql

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

psql -h ${HOST_IP} -p 5432 -d postgres -U henninb < master.sql > log.txt 2>&1

echo psql finance_db -U henninb -h ${HOST_IP}

exit 0
