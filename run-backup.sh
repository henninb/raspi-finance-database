#!/bin/sh

date=$(date '+%Y-%m-%d')

if [ "$OS" = "Darwin" ]; then
  HOST_IP=$(ipconfig getifaddr en0)
else
  HOST_IP=$(hostname -i | awk '{print $1}')
fi

echo postgresql database password
pg_dump -h "${HOST_IP}" -p 5432 -U henninb -W -F t -d finance_db > "finance_db-v12-3-${date}.tar"

echo scp "finance_db-v12-3-${date}.tar pi:/home/pi"

exit 0
