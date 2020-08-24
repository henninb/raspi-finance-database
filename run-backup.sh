#!/bin/sh

date=$(date '+%Y-%m-%d')
port=5432
version=v12-3

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(hostname -i | awk '{print $1}')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 [server] [port] [version]"
  echo "$0 192.168.100.124 5432 v12-4"
  exit 1
fi

if [ -n "$1" ]; then
  server=$1
fi

if [ -n "$2" ]; then
  port=$2
fi

if [ -n "$3" ]; then
  version=$3
fi

echo "server is '$server', port is set to '$port' on version '$version'."

echo postgresql database password
pg_dump -h "${server}" -p ${port} -U henninb -W -F t -d finance_db > "finance_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"

echo scp "finance_db-${version}-${date}.tar pi:/home/pi"

exit 0

The most important point to remember is that both dump and restore should be performed using the latest binaries. For example, if we need to migrate from version 9.3 to version 11, we should be using the pg_dump binary of PostgreSQL 11 to connect to 9.3
