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

-- actual 'Grand Total';
SELECT (A.debits - B.credits) AS TOTALS FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' and active_status  = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status = true) B;

UPDATE t_account SET totals = x.totals FROM (SELECT (A.debits - B.credits) AS totals FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' AND active_status = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' AND active_status = true) B) x WHERE t_account.account_name_owner = 'grand.total_dummy';


SELECT description FROM t_transaction WHERE description LIKE '%  %';
SELECT notes FROM t_transaction WHERE notes LIKE '%  %';

UPDATE t_transaction SET notes = replace(notes , '  ', ' ') WHERE notes LIKE '%  %';
COMMIT;

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

SELECT account_name_owner FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true)  group by account_name_owner having sum(amount) > 0;


-- find all the accounts that need payments
SELECT account_name_owner, SUM(amount) as totals FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true) or(transaction_state = 'outstanding' and account_type = 'credit' and description ='payment') group by account_name_owner having sum(amount) > 0 order by account_name_owner;

SELECT account_name_owner, amount as totals from t_transaction where transaction_state = 'outstanding' and account_type = 'credit' and description ='payment';

-- find all the accounts that need payments
SELECT account_name_owner FROM t_transaction WHERE transaction_state = 'cleared' and account_name_owner in (select account_name_owner from t_account where account_type = 'credit' and active_status = true) or (transaction_state = 'outstanding' and account_type = 'credit' and description ='payment') group by account_name_owner having sum(amount) > 0 order by account_name_owner;


SELECT 'centerpoint_brian', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE '%centerpoint%' and extract(year from transaction_date) = 2020;

SELECT 'xcel-energy_brian', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE '%xcel%' and extract(year from transaction_date) = 2020;

SELECT 'coon-rapids-water_brian', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 'city of coon rapids' and extract(year from transaction_date) = 2020;

SELECT 'coon-rapids-water_brian', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 'city of coon rapids' and extract(year from transaction_date) = 2020;

SELECT 'chase_kari', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 'allstate insurance' and extract(year from transaction_date) = 2020;

SELECT 'chase_kari', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 'century link' and extract(year from transaction_date) = 2020;

SELECT 'usbankcash_kari', (transaction_date + interval '1 year'), description, abs(amount) from t_transaction WHERE description LIKE 't-mobile.com' and extract(year from transaction_date) = 2020;

-- sequenence
SELECT setval('t_receipt_image_receipt_image_id_seq', max(receipt_image_id)) FROM t_receipt_image;
SELECT setval('t_receipt_image_receipt_image_id_seq', (SELECT MAX(receipt_image_id) FROM t_receipt_image)+1);
SELECT setval('t_transaction_transaction_id_seq', (SELECT MAX(transaction_id) FROM t_transaction)+1);
