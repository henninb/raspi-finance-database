-- select into example
SELECT count(*) into void_record_i from t_transaction WHERE amount='0.00' AND cleared=1 AND description = 'void' AND notes='';

-- select into example
SELECT count(*) into none_record_i from t_transaction WHERE amount='0.00' AND cleared=1 AND description = 'none' AND notes='';

--DELETE FROM t_transaction WHERE amount='0.00' AND cleared=1 AND description = 'void' AND notes='';
--DELETE FROM t_transaction WHERE amount='0.00' AND cleared=1 AND description = 'none' AND notes='';

--UPDATE t_transaction set amount = (amount * -1.0) where account_type = 'credit';

--UPDATE t_transaction SET account_id = x.account_id, account_type = x.account_type FROM (SELECT account_id, account_name_owner, account_type FROM t_account) x WHERE t_transaction.account_name_owner = x.account_name_owner;

-- total credits by account
SELECT account_name_owner, SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status  = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- total debits by account
SELECT account_name_owner, SUM(amount) AS credits FROM t_transaction WHERE account_type = 'debit' and active_status  = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- totals by account
SELECT account_name_owner, SUM(amount) AS totals FROM t_transaction where active_status = true GROUP BY account_name_owner ORDER BY account_name_owner;

-- total debits and total credits
SELECT A.debits AS DEBITS, B.credits AS CREDITS FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' and active_status = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status = true) B;

-- fix account type issue
ALTER TABLE t_transaction DISABLE TRIGGER ALL;
update t_transaction set account_type = 'credit' where account_name_owner = 'jcpenney_kari' and account_type = 'debit';
update t_account set account_type = 'credit' where account_name_owner = 'jcpenney_kari' and account_type = 'debit';
ALTER TABLE t_transaction ENABLE TRIGGER ALL;
commit;
select count(*) from t_transaction where account_name_owner = 'jcpenney_kari' and account_type = 'debit';

-- actual 'Grand Total';
SELECT (A.debits - B.credits) AS TOTALS FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' and active_status  = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status = true) B; 
     
UPDATE t_account SET totals = x.totals FROM (SELECT (A.debits - B.credits) AS totals FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' and active_status = true) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' and active_status = true) B) x WHERE t_account.account_name_owner = 'grand.total_dummy';


-- Looking for dupliate GUIDs;
--SELECT guid FROM t_transaction GROUP BY 1 HAVING COUNT(*) > 1;

CREATE OR REPLACE FUNCTION fn_ins_summary() RETURNS void AS $$
  INSERT INTO t_summary(summary_id, guid, account_name_owner, totals, totals_balanced, date_updated, date_added)
  (SELECT nextval('t_summary_summary_id_seq'), C.uuid AS guid, A.account_name_owner, A.totals AS totals, B.totals_balanced AS totals_balanced, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM
    ( SELECT account_name_owner, SUM(amount) AS totals FROM t_transaction GROUP BY account_name_owner ) A,
    ( SELECT account_name_owner, SUM(amount) AS totals_balanced FROM t_transaction WHERE cleared=1 GROUP BY account_name_owner ) B,
    ( SELECT uuid_generate_v4() AS uuid ) C
   WHERE A.account_name_owner = B.account_name_owner);
   UPDATE t_account SET totals = x.totals FROM (SELECT account_name_owner, SUM(amount) AS totals FROM t_transaction GROUP BY account_name_owner) x WHERE t_account.account_name_owner = x.account_name_owner;
   UPDATE t_account SET totals_balanced = x.totals_balanced FROM (SELECT account_name_owner, SUM(amount) AS totals_balanced FROM t_transaction WHERE cleared = 1 GROUP BY account_name_owner) x WHERE t_account.account_name_owner = x.account_name_owner;
   UPDATE t_account SET totals = x.totals FROM (SELECT (A.debits - B.credits) AS totals FROM
      ( SELECT SUM(amount) AS debits FROM t_transaction WHERE account_type = 'debit' ) A,
      ( SELECT SUM(amount) AS credits FROM t_transaction WHERE account_type = 'credit' ) B) x WHERE t_account.account_name_owner = 'grand.total_dummy';

$$ LANGUAGE SQL;

--RAISE NOTICE 'Populate Summary';
--SELECT NULL AS 'Populate Summary';
SELECT fn_ins_summary();

--RAISE NOTICE 'Summary by account';
--SELECT NULL AS 'Summary by account';
SELECT * FROM t_summary WHERE guid IN (SELECT guid FROM t_summary ORDER BY date_added DESC LIMIT 1) ORDER BY account_name_owner;

SELECT description FROM t_transaction WHERE description like '%  %';
SELECT notes FROM t_transaction WHERE notes like '%  %';

update t_transaction set notes = replace(notes , '  ', ' ') where notes like '%  %';
commit;

update t_transaction set description = replace(description , '  ', ' ') where description like '%  %';
commit;

--\copy (SELECT * FROM t_transaction) TO finance_db.csv WITH (FORMAT csv, HEADER true)

-- count of cleared transactions by week descending 
SELECT date_trunc('week', transaction_date::date) AS weekly, COUNT(*) FROM t_transaction where cleared = 1 GROUP BY weekly ORDER BY weekly desc;

-- count of cleared transactions spent by week 
SELECT date_trunc('week', transaction_date::date) AS weekly, sum(amount) FROM t_transaction where cleared = 1 and account_type = 'credit' and description != 'payment' and account_name_owner != 'medical' GROUP BY weekly ORDER BY weekly desc;

-- count of cleared transactions spent by month 
SELECT date_trunc('month', transaction_date::date) AS monthly, sum(amount) FROM t_transaction where cleared = 1 and account_type = 'credit' and description != 'payment' and account_name_owner != 'medical' GROUP BY monthly ORDER BY monthly desc;
