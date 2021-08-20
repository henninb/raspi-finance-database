#!/bin/sh

date=$(date '+%Y-%m-%d')
restore_filename=$1
port=5432
username=henninb

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 <restore-tar-file> [server] [port]"
  exit 1
fi

if [ ! -f "${restore_filename}" ]; then
  echo scp "pi:/home/pi/finance_db-v13-4-${date}.tar ."
  exit 1
fi

if [ -n "$2" ]; then
  server=$2
fi

if [ -n "$3" ]; then
  port=$3
fi

echo "database will restore to finance_db and finance_test_db from '${restore_filename}'"
echo "server is '$server', port is set to '$port'."
echo "Press enter to continue"
read -r x
echo "$x" > /dev/null

stty -echo
printf "Please enter the postgres '%s' password: " ${username}
read -r PGPASSWORD
export PGPASSWORD
stty echo
printf "\n"

printf '\set AUTOCOMMIT on\ndrop database finance_db; create database finance_db; ' | psql -h "${server}" -p "${port}" -d postgres -U "${username}"

printf '\set AUTOCOMMIT on\ndrop database finance_test_db; create database finance_test_db; ' | psql -h "${server}" -p "${port}" -d postgres -U "${username}"

pg_restore -h "${server}" -p "${port}" -U "${username}" -F t -d finance_db --verbose "${restore_filename}" | tee -a "finance_db-restore-${date}.log"
pg_restore -h "${server}" -p "${port}" -U "${username}" -F t -d finance_test_db --verbose "${restore_filename}" | tee -a "finance_test_db-restore-${date}.log"

exit 0
