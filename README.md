# on macos
createuser postgres

## restart
brew services restart postgres

## foreign key constraint

ALTER TABLE t_account ADD constraint unique_account_name_owner unique (account_name_owner);
ALTER TABLE t_transaction ADD CONSTRAINT fk_account_id_account_name_owner
   FOREIGN KEY(account_id, account_name_owner)
      REFERENCES t_account(account_id, account_name_owner);

select count(*) from t_transaction t, t_account a where a.account_id = t.account_id and a.account_name_owner != t.account_name_owner;

UPDATE t_transaction as t SET account_id = a.account_id FROM t_account as a WHERE a.account_id != t.account_id and a.account_name_owner = t.account_name_owner;

## autocommit
\echo :AUTOCOMMIT
\set AUTOCOMMIT off

## constraint
SELECT * FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_NAME='t_transaction' AND CONSTRAINT_TYPE = 'UNIQUE';
CREATE UNIQUE INDEX account_name_owner_idx on t_account(account_name_owner);

## select reoccuring transactions
select * from t_transaction where transaction_date > '2020-01-01' and reoccurring=true;
