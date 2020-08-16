# on macos
createuser postgres

## restart
brew services restart postgres

## autocommit
\echo :AUTOCOMMIT
\set AUTOCOMMIT off

## select reoccuring transactions
select account_name_owner, description, category, count(description) from t_transaction where transaction_date > '2020-01-01' and transaction_date < '2020-12-31' and reoccurring=true group by account_name_owner, description,category order by description;
