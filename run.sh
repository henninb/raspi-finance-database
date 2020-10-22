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

echo enter postgres user password to add finance_db objects
psql -h "${HOST_IP}" -p 5432 -d postgres -U henninb < master.sql | tee -a "finance_db-create-${date}.log"

echo enter postgres user password to add finance_test_db objects
psql -h "${HOST_IP}" -p 5432 -d postgres -U henninb < finance_test_db-create.sql | tee -a "finance_test_db-create-${date}.log"

echo psql finance_db -U henninb -h "${HOST_IP}" -p 5432

exit 0
