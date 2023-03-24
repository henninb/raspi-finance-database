-- select into example
--SELECT count(*) into void_record_i from t_transaction WHERE amount='0.00' AND transaction_state='cleared' AND description = 'void' AND notes='';

-- select into example
--SELECT count(*) into none_record_i from t_transaction WHERE amount='0.00' AND transaction_state='cleared' AND description = 'none' AND notes='';

--DELETE FROM t_transaction WHERE amount='0.00' AND transaction_state='cleared' AND description = 'void' AND notes='';
--DELETE FROM t_transaction WHERE amount='0.00' AND transaction_state='cleared' AND description 'none' AND notes='';

--UPDATE t_transaction set amount = (amount * -1.0) where account_type = 'credit';

--UPDATE t_transaction SET account_id = x.account_id, account_type = x.account_type FROM (SELECT account_id, account_name_owner, account_type FROM t_account) x WHERE t_transaction.account_name_owner = x.account_name_owner;

-- total credits by account
SELECT account_name_owner, SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' AND active_status  = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- total debits by account
SELECT account_name_owner, SUM(amount) AS credits FROM t_transaction WHERE account_type = 'debit' AND active_status  = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- totals by account
SELECT account_name_owner, SUM(amount) AS totals FROM t_transaction where active_status = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- total debits and total credits
SELECT A.debits AS DEBITS, B.credits AS CREDITS FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' AND active_status = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' AND active_status = true) B;

-- fix account type issue
ALTER TABLE t_transaction DISABLE TRIGGER ALL;
UPDATE t_transaction SET account_type = 'credit' WHERE account_name_owner = 'jcpenney_kari' AND account_type = 'debit';
UPDATE t_account SET account_type = 'credit' WHERE account_name_owner = 'jcpenney_kari' AND account_type = 'debit';
ALTER TABLE t_transaction ENABLE TRIGGER ALL;
commit;

SELECT count(*) FROM t_transaction WHERE account_name_owner = 'jcpenney_kari' AND account_type = 'debit';

-- select update actual 'Grand Total'
SELECT (A.debits - B.credits) AS TOTALS FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' and active_status  = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status = true) B;

UPDATE t_account SET totals = x.totals FROM (SELECT (A.debits - B.credits) AS totals FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' AND active_status = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' AND active_status = true) B) x WHERE t_account.account_name_owner = 'grand.total_dummy';


-- look for double spaces in the description
SELECT description FROM t_transaction WHERE description LIKE '%  %';
SELECT notes FROM t_transaction WHERE notes LIKE '%  %';

-- fix all doublespaces in the notes
UPDATE t_transaction SET notes = replace(notes , '  ', ' ') WHERE notes LIKE '%  %';
COMMIT;

-- remove spaces from description
UPDATE t_transaction SET description = replace(description , '  ', ' ') WHERE description LIKE '%  %';
COMMIT;

--\copy (SELECT * FROM t_transaction) TO finance_db.csv WITH (FORMAT csv, HEADER true)

-- count of cleared transactions by week descending
SELECT date_trunc('week', transaction_date::date) AS weekly, COUNT(*) FROM t_transaction WHERE transaction_state='cleared' GROUP BY weekly ORDER BY weekly desc;

-- count of cleared transactions spent by week
SELECT date_trunc('week', transaction_date::date) AS weekly, sum(amount) FROM t_transaction WHERE transaction_state='cleared' AND account_type = 'credit' AND description != 'payment' AND account_name_owner != 'medical' GROUP BY weekly ORDER BY weekly DESC;

-- count of cleared transactions spent by month
SELECT date_trunc('month', transaction_date::date) AS monthly, sum(amount) FROM t_transaction WHERE transaction_state='cleared' AND account_type = 'credit' AND description != 'payment' AND account_name_owner != 'medical' GROUP BY monthly ORDER BY monthly DESC;

-- find all the old future credits
select * from t_transaction  where transaction_state = 'future' and transaction_date < now() and account_type='credit';

-- find all the old outstanding credits
select * from t_transaction  where transaction_state = 'outstanding' and transaction_date < now() and account_type='credit';


-- find all the accounts that need payments
SELECT account_name_owner, SUM(amount) as totals FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true)  group by account_name_owner having sum(amount) > 0;

-- find accounts that need payments
SELECT account_name_owner FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true)  group by account_name_owner having sum(amount) > 0;

-- find all the accounts that need payments -- with details
SELECT account_name_owner, SUM(amount) as totals FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true) or(transaction_state = 'outstanding' and account_type = 'credit' and description ='payment') group by account_name_owner having sum(amount) > 0 order by account_name_owner;

SELECT account_name_owner, amount as totals from t_transaction where transaction_state = 'outstanding' and account_type = 'credit' and description ='payment';

-- find all the accounts that need payments
SELECT account_name_owner FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true) or (transaction_state = 'outstanding' and account_type = 'credit' and description ='payment') group by account_name_owner having sum(amount) > 0 order by account_name_owner;


-- find all centerpoint energy transactions in 2020
SELECT 'centerpoint_brian', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE '%centerpoint%' and extract(year from transaction_date) = 2020;

SELECT 'usbankcash_kari', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 't-mobile.com' and extract(year from transaction_date) = 2020;

-- sequenence
--SELECT setval('t_receipt_image_receipt_image_id_seq', max(receipt_image_id)) FROM t_receipt_image;

SELECT setval('t_receipt_image_receipt_image_id_seq', (SELECT MAX(receipt_image_id) FROM t_receipt_image)+1);
SELECT setval('t_transaction_transaction_id_seq', (SELECT MAX(transaction_id) FROM t_transaction)+1);
SELECT setval('t_payment_payment_id_seq', (SELECT MAX(payment_id) FROM t_payment)+1);
SELECT setval('t_account_account_id_seq', (SELECT MAX(account_id) FROM t_account)+1);
SELECT setval('t_category_category_id_seq', (SELECT MAX(category_id) FROM t_category)+1);
SELECT setval('t_description_description_id_seq', (SELECT MAX(description_id) FROM t_description)+1);
SELECT setval('t_parm_parm_id_seq', (SELECT MAX(parm_id) FROM t_parm)+1);

-- find dangling payments in source or destination
select * from t_payment where guid_source not in (select guid from t_transaction);
select * from t_payment where guid_destination not in (select guid from t_transaction);

-- find invalid receipt images
select receipt_image_id from t_receipt_image where receipt_image_id not in (select receipt_image_id from t_transaction);

-- set timezone to Chicago
SET timezone = 'America/Chicago';
COMMIT;
show timezone;

-- setup testing parameters, timezone and payment
INSERT INTO t_parm(parm_name, parm_value, active_status) VALUES('payment_account', 'bank_brian', true);
INSERT INTO t_parm(parm_name, parm_value, active_status) VALUES('timezone', 'America/Chicago', true);

-- clone a transacation for the next year based on a single transacation
INSERT INTO t_transaction(
  account_id, account_type, account_name_owner, guid, transaction_date, description, category, amount, transaction_state, reoccurring, reoccurring_type, active_status, notes, receipt_image_id, date_updated, date_added
)
SELECT
account_id, account_type, account_name_owner, uuid_generate_v4(), transaction_date + interval '365' day , description, category, amount, transaction_state, reoccurring, 'monthly', active_status, notes, receipt_image_id, now(), now()
FROM t_transaction where guid='d19885c4-e85e-49e6-a081-ffb54e97ef79';

-- Search and replace string in description
update t_transaction set description = replace(description, ' - *reoccur*', '') WHERE description LIKE ' - *reoccur*';

-- find all descriptions used more than 10 times
SELECT description, count(description) as cnt from t_transaction where description in (select description from t_description where active_status=true) group by description HAVING COUNT(description) < 11 order by cnt desc;

-- updates descriptions to false based on conditions on the t_transaction table
UPDATE t_description set active_status=false where description in (
select description from t_transaction where description in (select description from t_description where active_status=true) group by description HAVING COUNT(description) < 11);
COMMIT;

-- find all reoccurring transactions from 2020
SELECT description, (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE reoccurring = true and extract(year from transaction_date) = 2020;

-- find all the 2021 reoccurring_type transactions
SELECT description,count(description) from t_transaction where reoccurring_type != 'undefined' and extract(year from transaction_date) = 2021 group by description;


SELECT 'TRUNCATE ' || table_name || ';' FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';

select (left(encode(jpg_image, 'hex'), 44)) from t_receipt_image;

-- sum of credits vs debits
select DATE_TRUNC('month',transaction_date) as dt, sum(amount) from t_transaction where account_type='credit' group by DATE_TRUNC('month',transaction_date) order by dt;

select count(*) from t_transaction WHERE transaction_date BETWEEN SYMMETRIC '2022-08-01' AND '2022-08-31';

select sum(amount) from t_transaction where transaction_date BETWEEN SYMMETRIC '2022-09-01' AND '2022-09-30' and transaction_type='expense';

```
select A.to_month as month, A.to_sum as income, B.to_sum as expense, (A.to_sum - B.to_sum) as net from
(SELECT DATE_TRUNC('month',transaction_date) AS to_month, sum(abs(amount)) as to_sum
FROM t_transaction where transaction_type='income' and transaction_date > '2022-01-01'
GROUP BY DATE_TRUNC('month',transaction_date)) A,
(SELECT DATE_TRUNC('month',transaction_date) AS to_month, sum(abs(amount)) as to_sum
FROM t_transaction where transaction_type='expense' and transaction_date > '2022-01-01'
GROUP BY DATE_TRUNC('month',transaction_date)) B 
where A.to_month = B.to_month order by a.to_month;
```

-- rename an account
ALTER TABLE t_transaction DISABLE TRIGGER ALL;
UPDATE t_transaction SET account_name_owner = 'huntington-voice_brian' WHERE account_name_owner = 'huintington-voice_brian';
UPDATE t_account SET account_name_owner = 'huntington-voice_brian' WHERE account_name_owner = 'huintington-voice_brian';
ALTER TABLE t_transaction ENABLE TRIGGER ALL;
commit;


-- rename an account
ALTER TABLE t_transaction DISABLE TRIGGER ALL;
UPDATE t_transaction SET account_name_owner = 'capitalone-savings_brian' WHERE account_name_owner = 'ing-savings_brian';
UPDATE t_account SET account_name_owner = 'capitalone-savings_brian' WHERE account_name_owner = 'ing-savings_brian';
ALTER TABLE t_transaction ENABLE TRIGGER ALL;
commit;
