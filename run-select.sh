#!/bin/sh

date=$(date '+%Y-%m-%d')
port=5432

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(hostname -i | awk '{print $1}')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ]; then
  echo "Usage: $0 [server] [port]"
  exit 1
fi


if [ -n "$1" ]; then
  server=$1
fi

if [ -n "$2" ]; then
  port=$2
fi

echo "server is '$server', port is set to '$port'."
echo "Press enter to continue"
read -r x
echo "$x" > /dev/null

echo postgresql database password

# Fix collation version mismatches
echo "Refreshing collation versions..."
psql -h "${server}" -p "${port}" -U henninb -d postgres -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;" > /dev/null 2>&1
psql -h "${server}" -p "${port}" -U henninb -d template1 -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;" > /dev/null 2>&1
psql -h "${server}" -p "${port}" -U henninb -d finance_db -c "ALTER DATABASE finance_db REFRESH COLLATION VERSION;" > /dev/null 2>&1

psql -t -h "${server}" -p "${port}" -U henninb -F t -d finance_db < "select-receipt-image.sql" | tee -a "select-receipt-image-${date}.log"

exit 0
