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

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SET client_min_messages TO WARNING;

CREATE SEQUENCE t_payment_payment_id_seq START WITH 1001;

--TRUNCATE TABLE IF EXISTS t_payment;
DROP TABLE IF EXISTS t_payment;
CREATE TABLE IF NOT EXISTS t_payment(
  payment_id BIGINT DEFAULT nextval('t_payment_payment_id_seq') NOT NULL,
  account_name_owner TEXT NOT NULL,
  transaction_date DATE NOT NULL,
  amount DECIMAL(12,2) NOT NULL DEFAULT 0.0
);
ALTER TABLE t_payment ADD PRIMARY KEY (payment_id);
ALTER TABLE t_payment ADD CONSTRAINT payment_constraint UNIQUE (account_name_owner, transaction_date, amount);

--TRUNCATE TABLE IF EXISTS t_account;
CREATE SEQUENCE t_account_account_id_seq START WITH 1001;
DROP TABLE IF EXISTS t_account;
CREATE TABLE IF NOT EXISTS t_account(
  account_id BIGINT DEFAULT nextval('t_account_account_id_seq') NOT NULL,
  account_name_owner TEXT UNIQUE NOT NULL,
  account_name TEXT, -- NULL for now
  account_owner TEXT, -- NULL for now
  account_type TEXT NOT NULL,
  active_status BOOLEAN NOT NULL,
  moniker TEXT NOT NULL DEFAULT '',
  totals DECIMAL(12,2) DEFAULT 0.0,
  totals_balanced DECIMAL(12,2) DEFAULT 0.0,
  date_closed TIMESTAMP DEFAULT TO_TIMESTAMP(0),
  date_updated TIMESTAMP DEFAULT TO_TIMESTAMP(0),
  date_added TIMESTAMP DEFAULT TO_TIMESTAMP(0)
);
ALTER TABLE t_account ADD PRIMARY KEY (account_id);

--TODO: Not so sure an index is required here
CREATE UNIQUE INDEX account_name_owner_idx on t_account(account_name_owner);

CREATE OR REPLACE FUNCTION fn_upd_ts_account() RETURNS TRIGGER AS
$$
DECLARE
BEGIN
  RAISE NOTICE 'fn_upd_ts_account';
  NEW.date_updated := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS tr_upd_ts_account on t_account;
CREATE TRIGGER tr_upd_ts_account BEFORE UPDATE ON t_account FOR EACH ROW EXECUTE PROCEDURE fn_upd_ts_account();

CREATE OR REPLACE FUNCTION fn_ins_ts_account() RETURNS TRIGGER AS
$$
BEGIN
  RAISE NOTICE 'fn_ins_ts_account';
  NEW.date_added := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS tr_ins_ts_account on t_account;
CREATE TRIGGER tr_ins_ts_account BEFORE INSERT ON t_account FOR EACH ROW EXECUTE PROCEDURE fn_ins_ts_account();

CREATE SEQUENCE t_summary_summary_id_seq start with 1001;

--TRUNCATE TABLE IF EXISTS t_summary;
DROP TABLE IF EXISTS t_summary;
CREATE TABLE IF NOT EXISTS t_summary (
  summary_id BIGINT DEFAULT nextval('t_summary_summary_id_seq') NOT NULL,
  --summary_id serial PRIMARY KEY,
  guid TEXT UNIQUE NOT NULL,
  account_name_owner TEXT NOT NULL UNIQUE,
  totals DECIMAL(12,2) NOT NULL DEFAULT 0.0,
  totals_balanced DECIMAL(12,2) NOT NULL DEFAULT 0.0,
  date_updated TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
  date_added TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0)
);
ALTER TABLE t_summary ADD PRIMARY KEY (summary_id);

CREATE SEQUENCE t_category_category_id_seq start with 1001;

DROP TABLE IF EXISTS t_category;
CREATE TABLE IF NOT EXISTS t_category(
  category_id BIGINT DEFAULT nextval('t_category_category_id_seq') NOT NULL,
  category TEXT UNIQUE NOT NULL
);

DROP TABLE IF EXISTS t_transaction_categories;
CREATE TABLE IF NOT EXISTS t_transaction_categories(
  category_id BIGINT NOT NULL,
  transaction_id BIGINT NOT NULL,
  date_updated TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
  date_added TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0)
);

CREATE SEQUENCE t_transaction_transaction_id_seq start with 1001;

--TRUNCATE TABLE IF EXISTS t_transaction;
DROP TABLE IF EXISTS t_transaction;
CREATE TABLE IF NOT EXISTS t_transaction (
  transaction_id BIGINT DEFAULT nextval('t_transaction_transaction_id_seq') NOT NULL,
  account_id BIGINT NOT NULL DEFAULT -1,
  account_type TEXT NOT NULL,
  account_name_owner TEXT NOT NULL,
  guid TEXT NOT NULL UNIQUE,
  transaction_date DATE NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  amount DECIMAL(12,2) NOT NULL DEFAULT 0.0,
  cleared INTEGER NOT NULL DEFAULT 0,
  reoccurring BOOLEAN NOT NULL DEFAULT FALSE,
  notes TEXT NOT NULL DEFAULT '',
  date_updated TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
  date_added TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0)
);
ALTER TABLE t_transaction ADD PRIMARY KEY (transaction_id);

ALTER TABLE t_transaction ADD CONSTRAINT transaction_constraint UNIQUE (account_name_owner, transaction_date, description, category, amount, notes);

CREATE UNIQUE INDEX guid_idx ON t_transaction(guid);

CREATE OR REPLACE FUNCTION fn_ins_ts_transaction() RETURNS TRIGGER AS
$$
DECLARE
BEGIN
  --RAISE NOTICE 'fn_ins_ts_transaction';
  --TODO: add logic to insert account
  NEW.date_added := CURRENT_TIMESTAMP;
  NEW.date_updated := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS tr_ins_ts_transactions on t_transaction;
CREATE TRIGGER tr_ins_ts_transactions BEFORE INSERT ON t_transaction FOR EACH ROW EXECUTE PROCEDURE fn_ins_ts_transaction();

CREATE OR REPLACE FUNCTION fn_upd_ts_transaction() RETURNS TRIGGER AS
$$
DECLARE
BEGIN
  RAISE NOTICE 'fn_upd_ts_transaction';
  NEW.date_updated := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS tr_upd_ts_transactions on t_transaction;
CREATE TRIGGER tr_upd_ts_transactions BEFORE UPDATE ON t_transaction FOR EACH ROW EXECUTE PROCEDURE fn_upd_ts_transaction();
SELECT conrelid::regclass AS table_from, conname, pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE contype in ('f', 'p','c','u') ORDER BY contype;

INSERT INTO t_category(category) VALUES('adjustment');
INSERT INTO t_category(category) VALUES('allina');
INSERT INTO t_category(category) VALUES('assessment');
INSERT INTO t_category(category) VALUES('atm');
INSERT INTO t_category(category) VALUES('automotive');
INSERT INTO t_category(category) VALUES('automotive_tabs');
INSERT INTO t_category(category) VALUES('bill_pay');
INSERT INTO t_category(category) VALUES('bonus');
INSERT INTO t_category(category) VALUES('brokerage');
INSERT INTO t_category(category) VALUES('canceled');
INSERT INTO t_category(category) VALUES('cash');
INSERT INTO t_category(category) VALUES('chargeback');
INSERT INTO t_category(category) VALUES('check');
INSERT INTO t_category(category) VALUES('checking');
INSERT INTO t_category(category) VALUES('checks');
INSERT INTO t_category(category) VALUES('church');
INSERT INTO t_category(category) VALUES('communication');
INSERT INTO t_category(category) VALUES('credit');
INSERT INTO t_category(category) VALUES('deposit');
INSERT INTO t_category(category) VALUES('direct_deposit');
INSERT INTO t_category(category) VALUES('discoverbank');
INSERT INTO t_category(category) VALUES('dividend');
INSERT INTO t_category(category) VALUES('donation');
INSERT INTO t_category(category) VALUES('drivers_license');
INSERT INTO t_category(category) VALUES('electronics');
INSERT INTO t_category(category) VALUES('entertainment');
INSERT INTO t_category(category) VALUES('federal_tax_refund');
INSERT INTO t_category(category) VALUES('fishing_license');
INSERT INTO t_category(category) VALUES('fuel');
INSERT INTO t_category(category) VALUES('garbage');
INSERT INTO t_category(category) VALUES('general_merchandise');
INSERT INTO t_category(category) VALUES('groceries');
INSERT INTO t_category(category) VALUES('home_improvement');
INSERT INTO t_category(category) VALUES('house_payment');
INSERT INTO t_category(category) VALUES('house_repairs');
INSERT INTO t_category(category) VALUES('ingdirect');
INSERT INTO t_category(category) VALUES('insulation');
INSERT INTO t_category(category) VALUES('insurance');
INSERT INTO t_category(category) VALUES('insurance_auto');
INSERT INTO t_category(category) VALUES('insurance_home');
INSERT INTO t_category(category) VALUES('interest');
INSERT INTO t_category(category) VALUES('ira');
INSERT INTO t_category(category) VALUES('irs');
INSERT INTO t_category(category) VALUES('license');
INSERT INTO t_category(category) VALUES('liquor');
INSERT INTO t_category(category) VALUES('lodging');
INSERT INTO t_category(category) VALUES('maintenance');
INSERT INTO t_category(category) VALUES('meat');
INSERT INTO t_category(category) VALUES('medical');
INSERT INTO t_category(category) VALUES('mn_tax_return');
INSERT INTO t_category(category) VALUES('none');
INSERT INTO t_category(category) VALUES('nurse_license');
INSERT INTO t_category(category) VALUES('oil_change');
INSERT INTO t_category(category) VALUES('online');
INSERT INTO t_category(category) VALUES('orthodontist');
INSERT INTO t_category(category) VALUES('paycheck');
INSERT INTO t_category(category) VALUES('payment');
INSERT INTO t_category(category) VALUES('paypal');
INSERT INTO t_category(category) VALUES('phone');
INSERT INTO t_category(category) VALUES('pictures');
INSERT INTO t_category(category) VALUES('plumbing');
INSERT INTO t_category(category) VALUES('postage');
INSERT INTO t_category(category) VALUES('property_taxes');
INSERT INTO t_category(category) VALUES('rebate');
INSERT INTO t_category(category) VALUES('redeemed');
INSERT INTO t_category(category) VALUES('refund');
INSERT INTO t_category(category) VALUES('restaurant');
INSERT INTO t_category(category) VALUES('return');
INSERT INTO t_category(category) VALUES('reversal');
INSERT INTO t_category(category) VALUES('rewards');
INSERT INTO t_category(category) VALUES('savings');
INSERT INTO t_category(category) VALUES('school');
INSERT INTO t_category(category) VALUES('small_balance_payment');
INSERT INTO t_category(category) VALUES('state_tax_refund');
INSERT INTO t_category(category) VALUES('taxes');
INSERT INTO t_category(category) VALUES('utilities');
INSERT INTO t_category(category) VALUES('vacation');
INSERT INTO t_category(category) VALUES('vehicle');
INSERT INTO t_category(category) VALUES('withdrawal');
INSERT INTO t_category(category) VALUES('work_expense');
