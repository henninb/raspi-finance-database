#!/bin/sh

date=$(date '+%Y-%m-%d')
port=1521

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(hostname -i | awk '{print $1}')
fi

if [ $# -ne 0 ] && [ $# -ne 2 ]; then
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

echo oracle database password
echo @finance_db-create-oracle.sql | sqlplus -S henninb/monday1@192.168.100.208/ORCLCDB.localdomain

exit 0
