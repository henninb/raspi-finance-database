#!/bin/sh

date=$(date '+%Y-%m-%d')
port=5432
version=v12-5
username=henninb

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(hostname -i | awk '{print $1}')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 [server] [port] [version]"
  echo "$0 192.168.100.124 5432 v13-1"
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
pg_dump -h "${server}" -p "${port}" -U ${username} -W -F t -d finance_db > "finance_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"


echo "Please enter the '${username}' password: "
read -r PGPASSWORD
export PGPASSWORD

echo create finance_fresh_db
psql -h localhost -p "${port}" -U "${username}" postgres < finance_fresh_db-create.sql

#SELECT column_name  FROM information_schema.columns WHERE table_schema = 'public'  AND table_name   = 't_description';

echo description
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT description_id, description, active_status, date_updated, date_added from t_description ORDER BY description_id) TO 't_description.csv' CSV HEADER"
# psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "ALTER TABLE t_receipt_image DROP CONSTRAINT IF EXISTS fk_transaction; commit"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "ALTER TABLE t_transaction DROP CONSTRAINT IF EXISTS fk_receipt_image; commit"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_description FROM 't_description.csv' CSV HEADER; commit"

echo account
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT account_id, account_name_owner, account_name, account_owner, account_type, active_status, payment_required, moniker, future, outstanding, cleared, date_closed, date_updated, date_added from t_account ORDER BY account_id) TO 't_account.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_account FROM 't_account.csv' CSV HEADER; commit"


echo category
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT category_id, category, active_status, date_updated, date_added from t_category ORDER BY category_id) TO 't_category.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_category FROM 't_category.csv' CSV HEADER; commit"

#SELECT column_name  FROM information_schema.columns WHERE table_schema = 'public'  AND table_name   = 't_payment';


#SELECT column_name  FROM information_schema.columns WHERE table_schema = 'public'  AND table_name   = 't_parm';

echo parm
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT parm_id, parm_name, parm_value, active_status, date_updated, date_added from t_parm ORDER BY parm_id) TO 't_parm.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_parm FROM 't_parm.csv' CSV HEADER; commit"

echo transaction
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT transaction_id, account_id, account_type, account_name_owner, guid, transaction_date, due_date, description, category, amount, transaction_state, reoccurring_type, active_status, notes, receipt_image_id, date_updated, date_added from t_transaction ORDER BY transaction_id) TO 't_transaction.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_transaction FROM 't_transaction.csv' CSV HEADER; commit"

echo transaction_categories
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT category_id, transaction_id, date_updated, date_added from t_transaction_categories ORDER BY transaction_id) TO 't_transaction_categories.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_transaction_categories FROM 't_transaction_categories.csv' CSV HEADER; commit"

echo payment
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT payment_id, account_name_owner, transaction_date, amount, guid_source, guid_destination, active_status, date_updated, date_added from t_payment ORDER BY payment_id) TO 't_payment.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_payment FROM 't_payment.csv' CSV HEADER; commit"

echo receipt_image
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT receipt_image_id, transaction_id, image, thumbnail, image_format_type, active_status, date_updated, date_added from t_receipt_image ORDER BY receipt_image_id) TO 't_receipt_image.csv' CSV HEADER"

psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_receipt_image FROM 't_receipt_image.csv' CSV HEADER; commit"

echo Add fk_receipt_image constraint
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "alter table t_transaction add CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) ON DELETE CASCADE; commit"

echo postgresql database password
pg_dump -h localhost -p "${port}" -U ${username} -W -F t -d finance_fresh_db > "finance_fresh_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"

echo scp "finance_db-${version}-${date}.tar pi:/home/pi"

exit 0
