#!/bin/sh

date=$(date '+%Y-%m-%d')
port=5432
version=v15-1
username=henninb

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  # server=$(hostname -i | awk '{print $1}')
  server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 [server] [port] [version]"
  echo "$0 192.168.10.25 5432 v16-1"
  exit 1
fi

if [ ! -x "$(command -v psql)" ]; then
  echo "please install psql"
  # echo "then setup the database - sudo su - postgres"
  exit 2
fi

if [ -n "$1" ]; then
  server=$1
fi

if [ -n "$2" ]; then
  port=$2
fi

# if ! psql -h localhost -p "${port}" -U "${username}" "select * from t_transaction"; then
# fi

if [ -n "$3" ]; then
  version=$3
fi

echo Reminder: both dump and restore should be performed using the latest binaries
echo Example: migrate from version 9.3 to 11 - use pg_dump binary for 11 to connect to 9.3
echo "server is '$server', port is set to '$port' on version '$version'."

echo
stty -echo
printf "Please enter the postgres '%s' password: " ${username}
read -r PGPASSWORD
export PGPASSWORD
stty echo
printf "\n"

echo "${server}:${port}:finance_db:${username}:${PGPASSWORD}" > "$HOME/.pgpass"
echo "${server}:${port}:finance_fresh_db:${username}:${PGPASSWORD}" >> "$HOME/.pgpass"
chmod 600 "$HOME/.pgpass"

# echo postgresql database password
pg_dump -h "${server}" -p "${port}" -U ${username} -W -F t -d finance_db > "finance_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"

echo create finance_fresh_db
psql -h localhost -p "${port}" -U "${username}" postgres < finance_fresh_db-create.sql

#SELECT column_name  FROM information_schema.columns WHERE table_schema = 'public'  AND table_name   = 't_description';

echo description
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT description_id, description_name, owner, active_status, date_updated, date_added from t_description ORDER BY description_id) TO 't_description.csv' CSV HEADER"
# psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "ALTER TABLE t_receipt_image DROP CONSTRAINT IF EXISTS fk_transaction; commit"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "ALTER TABLE t_transaction DROP CONSTRAINT IF EXISTS fk_receipt_image; commit"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_description FROM 't_description.csv' CSV HEADER; commit"

echo account
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT account_id, account_name_owner, account_name, account_owner, account_type, active_status, payment_required, moniker, future, outstanding, cleared, date_closed, owner, date_updated, date_added from t_account ORDER BY account_id) TO 't_account.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_account FROM 't_account.csv' CSV HEADER; commit"

echo category
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT category_id, category_name, owner, active_status, date_updated, date_added from t_category ORDER BY category_id) TO 't_category.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_category FROM 't_category.csv' CSV HEADER; commit"

echo validationAmount
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT validation_id, account_id, validation_date, transaction_state, amount, owner, active_status, date_updated, date_added FROM t_validation_amount ORDER BY validation_id) TO 't_validation_amount.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_validation_amount FROM 't_validation_amount.csv' CSV HEADER; commit"

echo parameter
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT parameter_id, parameter_name, parameter_value, owner, active_status, date_updated, date_added from t_parameter ORDER BY parameter_id) TO 't_parameter.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_parameter FROM 't_parameter.csv' CSV HEADER; commit"

echo transaction
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT transaction_id, account_id, account_type, transaction_type, account_name_owner, guid, transaction_date, due_date, description, category, amount, transaction_state, reoccurring_type, active_status, notes, receipt_image_id, owner, date_updated, date_added from t_transaction ORDER BY transaction_id) TO 't_transaction.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_transaction FROM 't_transaction.csv' CSV HEADER; commit"

echo transaction_categories
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT category_id, transaction_id, owner, date_updated, date_added from t_transaction_categories ORDER BY transaction_id) TO 't_transaction_categories.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_transaction_categories FROM 't_transaction_categories.csv' CSV HEADER; commit"

echo payment
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT payment_id, account_name_owner, transaction_date, amount, guid_source, guid_destination, owner, active_status, date_updated, date_added from t_payment ORDER BY payment_id) TO 't_payment.csv' CSV HEADER"
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_payment FROM 't_payment.csv' CSV HEADER; commit"

echo receipt_image
psql -h "${server}" -p "${port}" -U ${username} finance_db -c "\copy (SELECT receipt_image_id, transaction_id, image, thumbnail, image_format_type, owner, active_status, date_updated, date_added from t_receipt_image ORDER BY receipt_image_id) TO 't_receipt_image.csv' CSV HEADER"

psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "\copy t_receipt_image FROM 't_receipt_image.csv' CSV HEADER; commit"

echo Add fk_receipt_image constraint
psql -h localhost -p "${port}" -U "${username}" finance_fresh_db -c "alter table t_transaction add CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) ON DELETE CASCADE; commit"

echo postgresql database password
pg_dump -h localhost -p "${port}" -U ${username} -W -F t -d finance_fresh_db > "finance_fresh_db-${version}-${date}.tar" | tee -a "finance-db-backup-${date}.log"

echo scp -p "finance_db-${version}-${date}.tar raspi:/home/pi/downloads/finance-db-bkp/"
scp -p "finance_db-${version}-${date}.tar" raspi:/home/pi/downloads/finance-db-bkp/

exit 0
