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

echo The most important point to remember is that both dump and restore should be performed using the latest binaries.
echo For example, if we need to migrate from version 9.3 to version 11, we should be using the pg_dump binary of PostgreSQL 11 to connect to 9.3
echo "server is '$server', port is set to '$port' on version '$version'."

echo postgresql database password
pg_dump -h "${server}" -p "${port}" -U henninb -W -F t -d finance_db > "finance_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"


echo create finance_fresh_db
psql -h localhost -p 5432 -U henninb postgres < finance_fresh_db-create.sql

echo account
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT account_id, account_name_owner, account_name, account_owner, account_type, active_status, moniker, totals, totals_balanced, date_closed, date_updated, date_added from t_account ORDER BY account_id) TO 't_account.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_account FROM 't_account.csv' CSV HEADER; commit"

echo transaction
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT transaction_id, account_id, account_type, account_name_owner, guid, transaction_date, description, category, amount, transaction_state, reoccurring, reoccurring_type, active_status, notes, receipt_image_id, date_updated, date_added from t_transaction ORDER BY transaction_id) TO 't_transaction.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_transaction FROM 't_transaction.csv' CSV HEADER; commit"

echo category
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT category_id, category, active_status, date_updated, date_added from t_category ORDER BY category_id) TO 't_category.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_category FROM 't_category.csv' CSV HEADER; commit"

echo payment
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT * from t_payment ORDER BY payment_id) TO 't_payment.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_payment FROM 't_payment.csv' CSV HEADER; commit"

echo parm
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT * from t_parm ORDER BY parm_id) TO 't_parm.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_parm FROM 't_parm.csv' CSV HEADER; commit"

echo receipt_image
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT * from t_receipt_image ORDER BY receipt_image_id) TO 't_receipt_image.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_receipt_image FROM 't_receipt_image.csv' CSV HEADER; commit"

echo description
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT * from t_description ORDER BY description_id) TO 't_description.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_description FROM 't_description.csv' CSV HEADER; commit"

echo transaction_categories
psql -h localhost -p 5432 -U henninb finance_db -c "\copy (SELECT * from t_transaction_categories ORDER BY transaction_id) TO 't_transaction_categories.csv' CSV HEADER"
psql -h localhost -p 5432 -U henninb finance_fresh_db -c "\copy t_transaction_categories FROM 't_transaction_categories.csv' CSV HEADER; commit"

echo scp "finance_db-${version}-${date}.tar pi:/home/pi"

exit 0
