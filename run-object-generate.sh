#!/bin/sh

date=$(date '+%Y-%m-%d')


cat > /tmp/sql-prod <<EOF
--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_db;
CREATE DATABASE finance_db;
GRANT ALL PRIVILEGES ON DATABASE finance_db TO henninb;

REVOKE CONNECT ON DATABASE finance_db FROM public;

\connect finance_db;

CREATE SCHEMA prod;

EOF

cat > /tmp/sql-test <<EOF
--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_test_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_test_db;
CREATE DATABASE finance_test_db;
GRANT ALL PRIVILEGES ON DATABASE finance_test_db TO henninb;

REVOKE CONNECT ON DATABASE finance_test_db FROM public;

\connect finance_test_db;

CREATE SCHEMA stage;
CREATE SCHEMA int;
CREATE SCHEMA func;

EOF

cat > /tmp/sql-fresh <<EOF
--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_test_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_fresh_db;
CREATE DATABASE finance_fresh_db;
GRANT ALL PRIVILEGES ON DATABASE finance_fresh_db TO henninb;

REVOKE CONNECT ON DATABASE finance_fresh_db FROM public;

\connect finance_fresh_db;

CREATE SCHEMA prod;

EOF

# Concatenate all migration files in order for prod schema
migration_dir="$HOME/projects/github.com/henninb/raspi-finance-endpoint/src/main/resources/db/migration/prod"
cat /tmp/sql-prod > finance_db-create.sql
for migration_file in $(ls "$migration_dir"/V*.sql | grep -v '.disabled$' | sort -V); do
    cat "$migration_file" >> finance_db-create.sql
done

cat /tmp/sql-test > finance_test_db-create.sql  
for migration_file in $(ls "$migration_dir"/V*.sql | grep -v '.disabled$' | sort -V); do
    cat "$migration_file" >> finance_test_db-create.sql
done

cat /tmp/sql-test "$HOME/projects/github.com/henninb/raspi-finance-endpoint/src/test/integration/resources/db/migration/int/V01__create-ddl-objects-int.sql" > finance_test_db-create-int.sql

cat /tmp/sql-test "$HOME/projects/github.com/henninb/raspi-finance-endpoint/src/test/functional/resources/db/migration/func/V01__create-ddl-objects-func.sql" > finance_test_db-create-func.sql

cat /tmp/sql-fresh > finance_fresh_db-create.sql
for migration_file in $(ls "$migration_dir"/V*.sql | grep -v '.disabled$' | sort -V); do
    cat "$migration_file" >> finance_fresh_db-create.sql
done

exit 0


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
psql -t -h "${server}" -p "${port}" -U henninb -F t -d finance_db < "select-receipt-image.sql" | tee -a "select-receipt-image-${date}.log"

exit 0
