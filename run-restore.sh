#!/bin/sh

date=$(date '+%Y-%m-%d')
restore_filename=$1
port=5432

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(hostname -i | awk '{print $1}')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 <restore-tar-file> [server] [port]"
  echo scp "pi:/home/pi/finance_db-v12-3-${date}.tar ."
  exit 1
fi

if [ ! -f "${restore_filename}" ]; then
  echo scp "pi:/home/pi/finance_db-v12-3-${date}.tar ."
  exit 1
fi

if [ -n "$2" ]; then
  server=$2
fi

if [ -n "$3" ]; then
  port=$3
fi

echo "database will restore to finance_db and finance_test_db"
echo "server is '$server', port is set to '$port'."
echo "Press enter to continue"
read -r x
echo "$x" > /dev/null

echo postgresql database password
if psql -h "${server}" -p "${port}" -d postgres -U henninb < finance_db-drop.sql; then
  echo postgresql database password
  pg_restore -h "${server}" -p "${port}" -U henninb -F t -d finance_db --verbose "${restore_filename}" | tee -a "finance_db-restore-${date}.log"
  pg_restore -h "${server}" -p "${port}" -U henninb -F t -d finance_test_db --verbose "${restore_filename}" | tee -a "finance_test_db-restore-${date}.log"
else
  echo "failed to drop the old database [finance_db]."
fi

exit 0
