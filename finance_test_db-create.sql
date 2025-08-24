--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_test_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_test_db;
CREATE DATABASE finance_test_db;
GRANT ALL PRIVILEGES ON DATABASE finance_test_db TO henninb;

REVOKE CONNECT ON DATABASE finance_test_db FROM public;

\connect finance_test_db;

CREATE SCHEMA stage;
CREATE SCHEMA int;
CREATE SCHEMA func;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SET client_min_messages TO WARNING;

CREATE SCHEMA IF NOT EXISTS public;

-------------
-- Account --
-------------
CREATE TABLE IF NOT EXISTS public.t_account
(
    account_id         BIGSERIAL PRIMARY KEY,
    account_name_owner TEXT UNIQUE                           NOT NULL,
    account_name       TEXT                                  NULL,     -- NULL for now 6/30/2021
    account_owner      TEXT                                  NULL,     -- NULL for now 6/30/2021
    account_type       TEXT          DEFAULT 'unknown'       NOT NULL,
    active_status      BOOLEAN       DEFAULT TRUE            NOT NULL,
    payment_required   BOOLEAN                               NULL DEFAULT TRUE,
    moniker            TEXT          DEFAULT '0000'          NOT NULL,
    future             NUMERIC(12, 2) DEFAULT 0.00           NULL,
    outstanding        NUMERIC(12, 2) DEFAULT 0.00           NULL,
    cleared            NUMERIC(12, 2) DEFAULT 0.00           NULL,
    date_closed        TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL, -- TODO: should be null by default
    validation_date    TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    owner              TEXT                                  NULL,
    date_updated       TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added         TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT unique_account_name_owner_account_id UNIQUE (account_id, account_name_owner, account_type),
    CONSTRAINT unique_account_name_owner_account_type UNIQUE (account_name_owner, account_type),
    CONSTRAINT ck_account_type CHECK (account_type IN ('debit', 'credit', 'undefined')),
    CONSTRAINT ck_account_type_lowercase CHECK (account_type = lower(account_type))
);

-- ALTER TABLE public.t_account ADD COLUMN payment_required   BOOLEAN     NULL     DEFAULT TRUE;

----------------------------
-- Validation Amount Date --
----------------------------
CREATE TABLE IF NOT EXISTS public.t_validation_amount
(
    validation_id     BIGSERIAL PRIMARY KEY,
    account_id        BIGINT                                NOT NULL,
    --validation_date   TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    validation_date   TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT '1970-01-01 00:00:00'::TIMESTAMP,
    transaction_state TEXT          DEFAULT 'undefined'     NOT NULL,
    amount            NUMERIC(12, 2) DEFAULT 0.00           NOT NULL,
    owner             TEXT                                  NULL,
    active_status     BOOLEAN       DEFAULT TRUE            NOT NULL,
    date_updated      TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    date_added        TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT ck_transaction_state CHECK (transaction_state IN ('outstanding', 'future', 'cleared', 'undefined')),
    CONSTRAINT fk_account_id FOREIGN KEY (account_id) REFERENCES public.t_account (account_id)
);

--------------
-- User     --
--------------
CREATE TABLE IF NOT EXISTS public.t_user
(
    user_id       BIGSERIAL PRIMARY KEY,
    username      TEXT UNIQUE                       NOT NULL,
    password      TEXT                              NOT NULL,
    first_name    TEXT                              NOT NULL,
    last_name     TEXT                              NOT NULL,
    active_status BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated  TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added    TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT ck_lowercase_username CHECK (username = lower(username))
);

--------------
-- Role     --
--------------
CREATE TABLE IF NOT EXISTS public.t_role
(
    role_id       BIGSERIAL PRIMARY KEY,
    role          TEXT UNIQUE                       NOT NULL,
    active_status BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated  TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added    TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT ck_lowercase_username CHECK (role = lower(role))
);

--------------
-- Category --
--------------
CREATE TABLE IF NOT EXISTS public.t_category
(
    category_id   BIGSERIAL PRIMARY KEY,
    category_name      TEXT UNIQUE                  NOT NULL,
    owner             TEXT                          NULL,
    active_status BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated  TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added    TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT ck_lowercase_category CHECK (category_name = lower(category_name))
);

-- ALTER TABLE public.t_category RENAME COLUMN category TO category_name;

-----------------
-- description --
-----------------
CREATE TABLE IF NOT EXISTS public.t_description
(
    description_id BIGSERIAL PRIMARY KEY,
    description_name    TEXT UNIQUE                       NOT NULL,
    owner               TEXT                              NULL,
    active_status       BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated        TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added          TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT t_description_description_lowercase_ck CHECK (description_name = lower(description_name))
);

-- ALTER TABLE public.t_description ADD COLUMN active_status      BOOLEAN        NOT NULL DEFAULT TRUE;
-- ALTER TABLE public.t_description RENAME COLUMN description TO description_name;

---------------------------
-- TransactionCategories --
---------------------------
CREATE TABLE IF NOT EXISTS public.t_transaction_categories
(
    category_id    BIGINT                            NOT NULL,
    transaction_id BIGINT                            NOT NULL,
    owner          TEXT                              NULL,
    date_updated   TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added     TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    PRIMARY KEY (category_id, transaction_id)
);

-------------------
-- ReceiptImage  --
-------------------
CREATE TABLE IF NOT EXISTS public.t_receipt_image
(
    receipt_image_id  BIGSERIAL PRIMARY KEY,
    transaction_id    BIGINT                            NOT NULL,
    image             BYTEA                             NOT NULL,
    thumbnail         BYTEA                             NOT NULL,
    image_format_type TEXT      DEFAULT 'undefined'     NOT NULL,
    owner             TEXT                              NULL,
    active_status     BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated      TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added        TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT ck_image_size CHECK (length(image) <= 1048576), -- 1024 kb file size limit
    CONSTRAINT ck_image_type CHECK (image_format_type IN ('jpeg', 'png', 'undefined'))
);

-- ALTER TABLE public.t_receipt_image rename column jpg_image to image;
-- ALTER TABLE public.t_receipt_image alter column thumbnail set not null;
-- ALTER TABLE public.t_receipt_image alter column image_format_type set not null;
-- ALTER TABLE public.t_receipt_image DROP CONSTRAINT ck_image_type_jpg;
-- ALTER TABLE public.t_receipt_image ADD COLUMN date_updated     TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0);
-- ALTER TABLE public.t_receipt_image ADD CONSTRAINT ck_image_size CHECK(length(image) <= 1_048_576);
-- select receipt_image_id, transaction_id, length(receipt_image)/1048576.0, left(encode(receipt_image,'hex'),100) from t_receipt_image;

-----------------
-- Transaction --
-----------------
--CREATE TYPE transaction_state_enum AS ENUM ('outstanding','future','cleared', 'undefined');
--CREATE TYPE account_type_enum AS ENUM ('credit','debit', 'undefined');
CREATE TABLE IF NOT EXISTS public.t_transaction
(
    transaction_id     BIGSERIAL PRIMARY KEY,
    account_id         BIGINT                                NOT NULL,
    account_type       TEXT          DEFAULT 'undefined'     NOT NULL,
    transaction_type   TEXT          DEFAULT 'undefined'     NOT NULL,
    account_name_owner TEXT                                  NOT NULL,
    guid               TEXT UNIQUE                           NOT NULL,
    transaction_date   DATE                                  NOT NULL,
    due_date           DATE                                  NULL,
    description        TEXT                                  NOT NULL,
    category           TEXT          DEFAULT ''              NOT NULL,
    amount             NUMERIC(12, 2) DEFAULT 0.00           NOT NULL,
    transaction_state  TEXT          DEFAULT 'undefined'     NOT NULL,
    reoccurring_type   TEXT          DEFAULT 'undefined'     NULL,
    active_status      BOOLEAN       DEFAULT TRUE            NOT NULL,
    notes              TEXT          DEFAULT ''              NOT NULL,
    receipt_image_id   BIGINT                                NULL,
    owner              TEXT                                  NULL,
    date_updated       TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added         TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT transaction_constraint UNIQUE (account_name_owner, transaction_date, description, category, amount,
                                              notes),
    CONSTRAINT t_transaction_description_lowercase_ck CHECK (description = lower(description)),
    CONSTRAINT t_transaction_category_lowercase_ck CHECK (category = lower(category)),
    CONSTRAINT t_transaction_notes_lowercase_ck CHECK (notes = lower(notes)),
    CONSTRAINT ck_transaction_state CHECK (transaction_state IN ('outstanding', 'future', 'cleared', 'undefined')),
    CONSTRAINT ck_account_type CHECK (account_type IN ('debit', 'credit', 'undefined')),
    CONSTRAINT ck_transaction_type CHECK (transaction_type IN ('expense', 'income', 'transfer', 'undefined')),
    CONSTRAINT ck_reoccurring_type CHECK (reoccurring_type IN
                                          ('annually', 'biannually', 'fortnightly', 'monthly', 'quarterly', 'onetime',
                                           'undefined')),
    CONSTRAINT fk_account_id_account_name_owner FOREIGN KEY (account_id, account_name_owner, account_type) REFERENCES public.t_account (account_id, account_name_owner, account_type) ON UPDATE CASCADE,
    CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES public.t_receipt_image (receipt_image_id) ON UPDATE CASCADE,
    CONSTRAINT fk_category_name FOREIGN KEY (category) REFERENCES public.t_category (category_name) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_description_name FOREIGN KEY (description) REFERENCES public.t_description (description_name) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Required to happen after the t_transaction table is created
ALTER TABLE public.t_receipt_image
    DROP CONSTRAINT IF EXISTS fk_transaction;
ALTER TABLE public.t_receipt_image
    ADD CONSTRAINT fk_transaction FOREIGN KEY (transaction_id) REFERENCES public.t_transaction (transaction_id) ON UPDATE CASCADE;

CREATE TABLE IF NOT EXISTS public.t_pending_transaction
(
    pending_transaction_id BIGSERIAL PRIMARY KEY,
    account_name_owner     TEXT                              NOT NULL,
    transaction_date       DATE                              NOT NULL,
    description            TEXT                              NOT NULL,
    amount                 NUMERIC(12, 2) DEFAULT 0.00       NOT NULL,
    review_status          TEXT          DEFAULT 'pending'   NOT NULL,
    owner                  TEXT                              NULL,
    date_added             TIMESTAMP     DEFAULT now()       NOT NULL,
    CONSTRAINT fk_pending_account FOREIGN KEY (account_name_owner)
        REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE,
    CONSTRAINT ck_review_status CHECK (review_status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT unique_pending_transaction_fields UNIQUE (account_name_owner, transaction_date, description, amount)
);

-------------
-- Payment --
-------------
-- TODO: update constraints
CREATE TABLE IF NOT EXISTS public.t_payment
(
    payment_id           BIGSERIAL PRIMARY KEY,
    account_name_owner   TEXT                                  NOT NULL,
    source_account       TEXT                                  NOT NULL,
    destination_account  TEXT                                  NOT NULL,
    transaction_date     DATE                                  NOT NULL,
    amount               NUMERIC(12, 2) DEFAULT 0.00           NOT NULL,
    guid_source          TEXT                                  NOT NULL,
    guid_destination     TEXT                                  NOT NULL,
    owner                TEXT                                  NULL,
    active_status        BOOLEAN       DEFAULT TRUE            NOT NULL,
    date_updated         TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added           TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT payment_constraint UNIQUE (account_name_owner, transaction_date, amount),
    CONSTRAINT fk_payment_guid_source FOREIGN KEY (guid_source) REFERENCES public.t_transaction (guid) ON UPDATE CASCADE,
    CONSTRAINT fk_payment_guid_destination FOREIGN KEY (guid_destination) REFERENCES public.t_transaction (guid) ON UPDATE CASCADE,
    CONSTRAINT fk_account_name_owner FOREIGN KEY (account_name_owner) REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE
);

--------------
-- Transfer --
--------------
CREATE TABLE IF NOT EXISTS public.t_transfer
(
    transfer_id         BIGSERIAL PRIMARY KEY,
    source_account      TEXT                                  NOT NULL,
    destination_account TEXT                                  NOT NULL,
    transaction_date    DATE                                  NOT NULL,
    amount              NUMERIC(12, 2) DEFAULT 0.00           NOT NULL,
    guid_source         TEXT                                  NOT NULL,
    guid_destination    TEXT                                  NOT NULL,
    owner               TEXT                                  NULL,
    active_status       BOOLEAN       DEFAULT TRUE            NOT NULL,
    date_updated        TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added          TIMESTAMP     DEFAULT TO_TIMESTAMP(0) NOT NULL,
    CONSTRAINT transfer_constraint UNIQUE (source_account, destination_account, transaction_date, amount),
    CONSTRAINT fk_transfer_guid_source FOREIGN KEY (guid_source) REFERENCES public.t_transaction (guid) ON UPDATE CASCADE,
    CONSTRAINT fk_transfer_guid_destination FOREIGN KEY (guid_destination) REFERENCES public.t_transaction (guid) ON UPDATE CASCADE,
    CONSTRAINT fk_source_account FOREIGN KEY (source_account) REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE,
    CONSTRAINT fk_destination_account FOREIGN KEY (destination_account) REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE
);

------------------
-- Parameter    --
------------------
CREATE TABLE IF NOT EXISTS public.t_parameter
(
    parameter_id       BIGSERIAL PRIMARY KEY,
    parameter_name     TEXT UNIQUE                       NOT NULL,
    parameter_value    TEXT                              NOT NULL,
    owner              TEXT                              NULL,
    active_status      BOOLEAN   DEFAULT TRUE            NOT NULL,
    date_updated       TIMESTAMP DEFAULT TO_TIMESTAMP(0) NOT NULL,
    date_added         TIMESTAMP                         NOT NULL DEFAULT TO_TIMESTAMP(0)
);

-- ALTER TABLE public.t_parameter ADD COLUMN active_status BOOLEAN NOT NULL DEFAULT TRUE;
-- INSERT into t_parameter(parameter_name, parameter_value) VALUES('payment_account', '');

SELECT setval('public.t_receipt_image_receipt_image_id_seq',
              (SELECT MAX(receipt_image_id) FROM public.t_receipt_image) + 1);
SELECT setval('public.t_transaction_transaction_id_seq', (SELECT MAX(transaction_id) FROM public.t_transaction) + 1);
SELECT setval('public.t_payment_payment_id_seq', (SELECT MAX(payment_id) FROM public.t_payment) + 1);
SELECT setval('public.t_account_account_id_seq', (SELECT MAX(account_id) FROM public.t_account) + 1);
SELECT setval('public.t_category_category_id_seq', (SELECT MAX(category_id) FROM public.t_category) + 1);
SELECT setval('public.t_description_description_id_seq', (SELECT MAX(description_id) FROM public.t_description) + 1);
SELECT setval('public.t_parameter_parameter_id_seq', (SELECT MAX(parameter_id) FROM public.t_parameter) + 1);
SELECT setval('public.t_validation_amount_validation_id_seq',
              (SELECT MAX(validation_id) FROM public.t_validation_amount) + 1);

CREATE OR REPLACE FUNCTION fn_update_transaction_categories()
    RETURNS TRIGGER
    SET SCHEMA 'public'
    LANGUAGE PLPGSQL
AS
$$
    BEGIN
      NEW.date_updated := CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
$$;

CREATE OR REPLACE FUNCTION fn_insert_transaction_categories()
    RETURNS TRIGGER
    SET SCHEMA 'public'
    LANGUAGE PLPGSQL
AS
$$
    BEGIN
      NEW.date_updated := CURRENT_TIMESTAMP;
      NEW.date_added := CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
$$;


CREATE OR REPLACE FUNCTION rename_account_owner(
    p_old_name VARCHAR,
    p_new_name VARCHAR
)
RETURNS VOID
SET SCHEMA 'public'
LANGUAGE PLPGSQL
AS
$$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET account_name_owner = $1 WHERE account_name_owner = $2'
    USING p_new_name, p_old_name;

    EXECUTE 'UPDATE t_account SET account_name_owner = $1 WHERE account_name_owner = $2'
    USING p_new_name, p_old_name;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$$;


CREATE OR REPLACE FUNCTION disable_account_owner(
    p_new_name VARCHAR
)
RETURNS VOID
SET SCHEMA 'public'
LANGUAGE PLPGSQL
AS
$$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET active_status = false WHERE account_name_owner = $1'
    USING p_new_name;

    EXECUTE 'UPDATE t_account SET active_status = false WHERE account_name_owner = $1'
    USING p_new_name;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$$;


DROP TRIGGER IF EXISTS tr_insert_transaction_categories ON public.t_transaction_categories;
CREATE TRIGGER tr_insert_transaction_categories
    BEFORE INSERT
    ON public.t_transaction_categories
    FOR EACH ROW
EXECUTE PROCEDURE fn_insert_transaction_categories();

DROP TRIGGER IF EXISTS tr_update_transaction_categories ON public.t_transaction_categories;
CREATE TRIGGER tr_update_transaction_categories
    BEFORE UPDATE
    ON public.t_transaction_categories
    FOR EACH ROW
EXECUTE PROCEDURE fn_update_transaction_categories();

COMMIT;
-- check for locks
-- SELECT pid, usename, pg_blocking_pids(pid) as blocked_by, query as blocked_query from pg_stat_activity where cardinality(pg_blocking_pids(pid)) > 0;

--SELECT * from t_transaction where transaction_state = 'cleared' and transaction_date > now();
--SELECT * from t_transaction where transaction_state in ('future', 'outstanding') and transaction_date < now();
-- Performance indexes for production database (transactional part)
-- Migration: V02__add-performance-indexes.sql
-- Purpose: Add critical indexes to improve query performance for financial data operations
-- Note: Concurrent index creation moved to V03 migration

SET client_min_messages TO WARNING;

-- ================================
-- NON-CONCURRENT INDEXES (TRANSACTIONAL)
-- ================================

-- Note: All indexes will be created with CONCURRENTLY in V03 migration
-- This migration creates the foundation for index tracking-- Drop payment_constraint from t_payment table
-- This constraint ensures uniqueness based on account_name_owner, transaction_date, and amount
-- Removing this to allow duplicate payments with same details

ALTER TABLE public.t_payment DROP CONSTRAINT payment_constraint;-- Remove obsolete account_name_owner column from t_payment
-- and enforce integrity using source_account and destination_account instead.

BEGIN;

-- 1) Backfill destination_account from account_name_owner where needed
UPDATE public.t_payment p
SET destination_account = p.account_name_owner
WHERE (p.destination_account IS NULL OR btrim(p.destination_account) = '')
  AND p.account_name_owner IS NOT NULL;

-- 2) Normalize destination/source to lowercase
UPDATE public.t_payment p SET destination_account = lower(p.destination_account) WHERE p.destination_account IS NOT NULL;
UPDATE public.t_payment p SET source_account = lower(p.source_account) WHERE p.source_account IS NOT NULL;

-- 3) Normalize hyphens to underscores if that makes them match an existing account
UPDATE public.t_payment p
SET destination_account = REPLACE(p.destination_account, '-', '_')
WHERE NOT EXISTS (
    SELECT 1 FROM public.t_account a WHERE a.account_name_owner = p.destination_account
)
AND EXISTS (
    SELECT 1 FROM public.t_account a WHERE a.account_name_owner = REPLACE(p.destination_account, '-', '_')
);

UPDATE public.t_payment p
SET source_account = REPLACE(p.source_account, '-', '_')
WHERE NOT EXISTS (
    SELECT 1 FROM public.t_account a WHERE a.account_name_owner = p.source_account
)
AND EXISTS (
    SELECT 1 FROM public.t_account a WHERE a.account_name_owner = REPLACE(p.source_account, '-', '_')
);

-- Add FKs for source_account and destination_account to t_account(account_name_owner)
-- 4) Add new FKs as NOT VALID first, then validate after data cleanup
ALTER TABLE public.t_payment
    ADD CONSTRAINT fk_payment_source_account FOREIGN KEY (source_account)
        REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE NOT VALID;

ALTER TABLE public.t_payment
    ADD CONSTRAINT fk_payment_destination_account FOREIGN KEY (destination_account)
        REFERENCES public.t_account (account_name_owner) ON UPDATE CASCADE NOT VALID;

-- Validate constraints (will check all existing rows)
ALTER TABLE public.t_payment VALIDATE CONSTRAINT fk_payment_source_account;
ALTER TABLE public.t_payment VALIDATE CONSTRAINT fk_payment_destination_account;

-- Add a new unique constraint to prevent duplicate payments per destination account/date/amount
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'payment_constraint_destination'
    ) THEN
        ALTER TABLE public.t_payment
            ADD CONSTRAINT payment_constraint_destination UNIQUE (destination_account, transaction_date, amount);
    END IF;
END $$;

-- 6) Drop old FK and column only after new constraints are in place
ALTER TABLE public.t_payment
    DROP CONSTRAINT IF EXISTS fk_account_name_owner;

ALTER TABLE public.t_payment
    DROP COLUMN IF EXISTS account_name_owner;

COMMIT;
-- Drop obsolete foreign key on t_payment(account_name_owner)
-- Safe even if already removed

ALTER TABLE public.t_payment
    DROP CONSTRAINT IF EXISTS fk_account_name_owner;

