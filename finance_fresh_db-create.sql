--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_fresh_db;
CREATE DATABASE finance_fresh_db;
GRANT ALL PRIVILEGES ON DATABASE finance_fresh_db TO henninb;

REVOKE CONNECT ON DATABASE finance_fresh_db FROM public;

\connect finance_fresh_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SET client_min_messages TO WARNING;

-------------
-- Account --
-------------
CREATE TABLE IF NOT EXISTS t_account
(
    account_id         BIGSERIAL PRIMARY KEY,
    account_name_owner TEXT UNIQUE NOT NULL,
    account_name       TEXT, -- NULL for now
    account_owner      TEXT, -- NULL for now
    account_type       TEXT        NOT NULL DEFAULT 'unknown',
    active_status      BOOLEAN     NOT NULL DEFAULT TRUE,
    moniker            TEXT        NOT NULL DEFAULT '0000',
    totals             DECIMAL(12, 2)       DEFAULT 0.0,
    totals_balanced    DECIMAL(12, 2)       DEFAULT 0.0,
    date_closed        TIMESTAMP            DEFAULT TO_TIMESTAMP(0),
    date_updated       TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added         TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT unique_account_name_owner_account_id UNIQUE (account_id, account_name_owner, account_type),
    CONSTRAINT unique_account_name_owner_account_type UNIQUE (account_name_owner, account_type),
    CONSTRAINT ck_account_type CHECK (account_type IN ('debit', 'credit', 'undefined')),
    CONSTRAINT ck_account_type_lowercase CHECK (account_type = lower(account_type))
);

--------------
-- Category --
--------------
CREATE TABLE IF NOT EXISTS t_category
(
    category_id   BIGSERIAL PRIMARY KEY,
    category      TEXT UNIQUE NOT NULL,
    active_status BOOLEAN     NOT NULL DEFAULT TRUE,
    date_updated  TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added    TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT ck_lowercase_category CHECK (category = lower(category))
);

---------------------------
-- TransactionCategories --
---------------------------
CREATE TABLE IF NOT EXISTS t_transaction_categories
(
    category_id    BIGINT    NOT NULL,
    transaction_id BIGINT    NOT NULL,
    date_updated   TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added     TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
    PRIMARY KEY (category_id, transaction_id)
);

-------------------
-- ReceiptImage  --
-------------------
CREATE TABLE IF NOT EXISTS t_receipt_image
(
    receipt_image_id BIGSERIAL PRIMARY KEY,
    transaction_id   BIGINT    NOT NULL,
    jpg_image        BYTEA     NOT NULL,                         -- ADD the not NULL constraint
    active_status    BOOLEAN   NOT NULL DEFAULT TRUE,
    date_updated     TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added       TIMESTAMP NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT ck_jpg_size CHECK (length(jpg_image) <= 1048576), -- 1024 kb file size limit
    CONSTRAINT ck_image_type_jpg CHECK (left(encode(jpg_image, 'hex'), 44) = '646174613a696d6167652f6a7065673b626173653634')
);

-----------------
-- Transaction --
-----------------
--CREATE TYPE transaction_state_enum AS ENUM ('outstanding','future','cleared', 'undefined');
--CREATE TYPE account_type_enum AS ENUM ('credit','debit', 'undefined');
CREATE TABLE IF NOT EXISTS t_transaction
(
    transaction_id     BIGSERIAL PRIMARY KEY,
    account_id         BIGINT         NOT NULL,
    account_type       TEXT           NOT NULL DEFAULT 'undefined',
    account_name_owner TEXT           NOT NULL,
    guid               TEXT           NOT NULL UNIQUE,
    transaction_date   DATE           NOT NULL,
    description        TEXT           NOT NULL,
    category           TEXT           NOT NULL DEFAULT '',
    amount             DECIMAL(12, 2) NOT NULL DEFAULT 0.0,
    transaction_state  TEXT           NOT NULL DEFAULT 'undefined',
    reoccurring        BOOLEAN        NOT NULL DEFAULT FALSE,
    reoccurring_type   TEXT           NULL     DEFAULT 'undefined',
    active_status      BOOLEAN        NOT NULL DEFAULT TRUE,
    notes              TEXT           NOT NULL DEFAULT '',
    receipt_image_id   BIGINT         NULL,
    date_updated       TIMESTAMP      NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added         TIMESTAMP      NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT transaction_constraint UNIQUE (account_name_owner, transaction_date, description, category, amount,
                                              notes),
    CONSTRAINT t_transaction_description_lowercase_ck CHECK (description = lower(description)),
    CONSTRAINT t_transaction_category_lowercase_ck CHECK (category = lower(category)),
    CONSTRAINT t_transaction_notes_lowercase_ck CHECK (notes = lower(notes)),
    CONSTRAINT ck_transaction_state CHECK (transaction_state IN ('outstanding', 'future', 'cleared', 'undefined')),
    CONSTRAINT ck_account_type CHECK (account_type IN ('debit', 'credit', 'undefined')),
    CONSTRAINT ck_reoccurring_type CHECK (reoccurring_type IN
                                          ('annually', 'bi-annually', 'every_two_weeks', 'monthly', 'undefined'))
);

-- example
-- ALTER TABLE t_transaction ADD CONSTRAINT ck_reoccurring_type CHECK (reoccurring_type IN ('annually', 'bi-annually', 'every_two_weeks', 'monthly', 'undefined'));
-- ALTER TABLE t_transaction ADD COLUMN reoccurring_type TEXT NULL DEFAULT 'undefined';
-- ALTER TABLE t_transaction DROP COLUMN receipt_image_id;

-------------
-- Payment --
-------------
CREATE TABLE IF NOT EXISTS t_payment
(
    payment_id         BIGSERIAL PRIMARY KEY,
    account_name_owner TEXT           NOT NULL,
    transaction_date   DATE           NOT NULL,
    amount             DECIMAL(12, 2) NOT NULL DEFAULT 0.0,
    guid_source        TEXT           NOT NULL,
    guid_destination   TEXT           NOT NULL,
    --TODO: bh 11/11/2020 - need to add this field
    --active_status      BOOLEAN        NOT NULL DEFAULT TRUE,
    date_updated       TIMESTAMP      NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added         TIMESTAMP      NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT payment_constraint UNIQUE (account_name_owner, transaction_date, amount)
);

-------------
-- Parm --
-------------
CREATE TABLE IF NOT EXISTS t_parm
(
    parm_id       BIGSERIAL PRIMARY KEY,
    parm_name     TEXT UNIQUE NOT NULL,
    parm_value    TEXT        NOT NULL,
    active_status BOOLEAN     NOT NULL DEFAULT TRUE,
    date_updated  TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added    TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0)
);

-- example
-- ALTER TABLE t_parm ADD COLUMN active_status BOOLEAN NOT NULL DEFAULT TRUE;
-- insert into t_parm(parm_name, parm_value) VALUES('payment_account', '');

-----------------
-- description --
-----------------
CREATE TABLE IF NOT EXISTS t_description
(
    description_id BIGSERIAL PRIMARY KEY,
    description    TEXT UNIQUE NOT NULL,
    active_status  BOOLEAN     NOT NULL DEFAULT TRUE,
    date_updated   TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    date_added     TIMESTAMP   NOT NULL DEFAULT TO_TIMESTAMP(0),
    CONSTRAINT t_description_description_lowercase_ck CHECK (description = lower(description))
);

--ALTER TABLE t_receipt_image ADD CONSTRAINT fk_transaction FOREIGN KEY (transaction_id) REFERENCES t_transaction (transaction_id) ON DELETE CASCADE;
--ALTER TABLE t_description ADD CONSTRAINT fk_account_id_account_name_owner FOREIGN KEY (account_id, account_name_owner, account_type) REFERENCES t_account (account_id, account_name_owner, account_type) ON DELETE CASCADE;
--ALTER TABLE t_description ADD CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES t_receipt_image (receipt_image_id) ON DELETE CASCADE;
--ALTER TABLE t_description ADD CONSTRAINT fk_category FOREIGN KEY (category) REFERENCES t_category (category) ON DELETE CASCADE;
--ALTER TABLE t_payment ADD CONSTRAINT fk_guid_source FOREIGN KEY (guid_source) REFERENCES t_transaction (guid);
--ALTER TABLE t_payment ADD CONSTRAINT fk_guid_destination FOREIGN KEY (guid_destination) REFERENCES t_transaction (guid);


COMMIT;
