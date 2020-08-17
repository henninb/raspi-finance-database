# on macos
createuser postgres

## restart
brew services restart postgres

## autocommit
\echo :AUTOCOMMIT
\set AUTOCOMMIT off

## select reoccuring transactions
select account_name_owner, description, category, count(description) from t_transaction where transaction_date > '2020-01-01' and transaction_date < '2020-12-31' and reoccurring=true group by account_name_owner, description,category order by description;

## select by month for bill_pay
select * from t_transaction where category ='bill_pay' and transaction_date > '2020-08-01' and transaction_date < '2020-08-31' and account_name_owner = 'bcu-checking_brian';

## copy a row
insert into t_transaction(account_id, account_type, account_name_owner, guid, transaction_date, description, category, amount, cleared, reoccurring, notes) SELECT account_id, account_type, account_name_owner, uuid_generate_v4(), '2020-08-31', description, category, 0.00, -1, reoccurring, notes FROM t_transaction where guid='9a88f2a8-5c99-49a3-9c9a-348cd770579a';

## lower case
UPDATE t_transaction SET category = LOWER(category) WHERE category != LOWER(category);
UPDATE t_transaction SET description = LOWER(description) WHERE description != LOWER(description);

UPDATE t_transaction SET notes = LOWER(notes) WHERE notes != LOWER(notes);

ALTER TABLE t_transaction ADD CONSTRAINT t_transaction_description_lowercase_ck CHECK (description = lower(description));

ALTER TABLE t_transaction ADD CONSTRAINT t_transaction_category_lowercase_ck CHECK (category = lower(category));

ALTER TABLE t_transaction ADD CONSTRAINT t_transaction_notes_lowercase_ck CHECK (notes = lower(notes));
