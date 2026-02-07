--set client_min_messages = warning;
--\d+ (shows sequence)
--epoch
--select extract(epoch from date_added) from t_transaction;
--select date_part('epoch', date_added) from t_transaction;
--SELECT EXTRACT(EPOCH FROM TIMESTAMP '2016-10-25T00:14:30.000');
--extract(epoch from date_trunc('month', current_timestamp)
--REVOKE CONNECT ON DATABASE finance_test_db FROM PUBLIC, henninb;

--TO_TIMESTAMP('1538438975')

DROP DATABASE IF EXISTS finance_fresh_db;
CREATE DATABASE finance_fresh_db;
GRANT ALL PRIVILEGES ON DATABASE finance_fresh_db TO henninb;

REVOKE CONNECT ON DATABASE finance_fresh_db FROM public;

\connect finance_fresh_db;

CREATE SCHEMA prod;

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

-- V07: Extend AccountType enum with comprehensive account types
-- Add support for medical, financial, investment, and utility account types

-- Drop existing constraint
ALTER TABLE public.t_account
DROP CONSTRAINT IF EXISTS ck_account_type;

-- Add new comprehensive account type constraint
ALTER TABLE public.t_account
ADD CONSTRAINT ck_account_type
CHECK (account_type IN (
    -- Existing types (preserve compatibility)
    'credit', 'debit', 'undefined',

    -- Banking/Traditional Accounts
    'checking', 'savings', 'credit_card', 'certificate', 'money_market',

    -- Investment Accounts
    'brokerage', 'retirement_401k', 'retirement_ira', 'retirement_roth', 'pension',

    -- Medical/Healthcare Accounts
    'hsa', 'fsa', 'medical_savings',

    -- Loan/Debt Accounts
    'mortgage', 'auto_loan', 'student_loan', 'personal_loan', 'line_of_credit',

    -- Utility/Service Accounts
    'utility', 'prepaid', 'gift_card',

    -- Business Accounts
    'business_checking', 'business_savings', 'business_credit',

    -- Other/Miscellaneous
    'cash', 'escrow', 'trust'
));

-- Ensure lowercase constraint still exists
ALTER TABLE public.t_account
DROP CONSTRAINT IF EXISTS ck_account_type_lowercase;

ALTER TABLE public.t_account
ADD CONSTRAINT ck_account_type_lowercase
CHECK (account_type = lower(account_type));

-- Add index for performance on account_type queries
CREATE INDEX IF NOT EXISTS idx_account_type ON public.t_account(account_type);

-- Add index for account category queries (will be useful for reporting)
-- This will support future category-based filtering
CREATE INDEX IF NOT EXISTS idx_account_active_type ON public.t_account(active_status, account_type)
WHERE active_status = true;-- V08: Create Medical Provider table
-- Medical provider information for healthcare expense tracking

CREATE TABLE IF NOT EXISTS public.t_medical_provider (
    provider_id         BIGSERIAL PRIMARY KEY,
    provider_name       TEXT NOT NULL,
    provider_type       TEXT NOT NULL DEFAULT 'general',
    specialty           TEXT,
    npi                 TEXT UNIQUE, -- National Provider Identifier
    tax_id              TEXT, -- Tax ID/EIN for business providers

    -- Address information
    address_line1       TEXT,
    address_line2       TEXT,
    city               TEXT,
    state              TEXT,
    zip_code           TEXT,
    country            TEXT DEFAULT 'US',

    -- Contact information
    phone              TEXT,
    fax                TEXT,
    email              TEXT,
    website            TEXT,

    -- Provider details
    network_status     TEXT DEFAULT 'unknown', -- in_network, out_of_network, unknown
    billing_name       TEXT, -- Name used for billing/claims
    notes              TEXT,

    -- Audit and status fields
    active_status      BOOLEAN DEFAULT TRUE NOT NULL,
    date_added         TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated       TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- Constraints
    CONSTRAINT ck_provider_type CHECK (provider_type IN (
        'general', 'specialist', 'hospital', 'pharmacy', 'laboratory',
        'imaging', 'urgent_care', 'emergency', 'mental_health', 'dental',
        'vision', 'physical_therapy', 'other'
    )),
    CONSTRAINT ck_network_status CHECK (network_status IN (
        'in_network', 'out_of_network', 'unknown'
    )),
    CONSTRAINT ck_provider_name_lowercase CHECK (provider_name = lower(provider_name)),
    CONSTRAINT ck_provider_name_not_empty CHECK (length(trim(provider_name)) > 0),
    CONSTRAINT ck_npi_format CHECK (npi IS NULL OR (npi ~ '^[0-9]{10}$')), -- NPI is 10 digits
    CONSTRAINT ck_zip_code_format CHECK (zip_code IS NULL OR (zip_code ~ '^[0-9]{5}(-[0-9]{4})?$')),
    CONSTRAINT ck_phone_format CHECK (phone IS NULL OR (length(phone) >= 10))
);

-- Indexes for performance
CREATE INDEX idx_medical_provider_name ON public.t_medical_provider(provider_name);
CREATE INDEX idx_medical_provider_type ON public.t_medical_provider(provider_type);
CREATE INDEX idx_medical_provider_specialty ON public.t_medical_provider(specialty) WHERE specialty IS NOT NULL;
CREATE INDEX idx_medical_provider_npi ON public.t_medical_provider(npi) WHERE npi IS NOT NULL;
CREATE INDEX idx_medical_provider_active ON public.t_medical_provider(active_status, provider_name) WHERE active_status = true;
CREATE INDEX idx_medical_provider_network ON public.t_medical_provider(network_status, provider_type);
CREATE INDEX idx_medical_provider_location ON public.t_medical_provider(state, city) WHERE state IS NOT NULL AND city IS NOT NULL;

-- Insert common medical provider types for initial data
INSERT INTO public.t_medical_provider (provider_name, provider_type, specialty, network_status) VALUES
('unknown_provider', 'general', NULL, 'unknown'),
('pharmacy_generic', 'pharmacy', 'retail_pharmacy', 'unknown'),
('urgent_care_generic', 'urgent_care', NULL, 'unknown'),
('hospital_generic', 'hospital', NULL, 'unknown'),
('laboratory_generic', 'laboratory', 'general_lab', 'unknown');-- V09: Create Family Member table
-- Family member tracking for medical expense attribution

CREATE TABLE IF NOT EXISTS public.t_family_member (
    family_member_id    BIGSERIAL PRIMARY KEY,
    owner               TEXT NOT NULL,
    member_name         TEXT NOT NULL,
    relationship        TEXT NOT NULL DEFAULT 'self',
    date_of_birth       DATE,
    insurance_member_id TEXT,

    -- Medical identifiers
    ssn_last_four      TEXT,
    medical_record_number TEXT,

    -- Audit and status fields
    active_status      BOOLEAN DEFAULT TRUE NOT NULL,
    date_added         TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated       TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- Constraints
    CONSTRAINT ck_family_relationship CHECK (relationship IN (
        'self', 'spouse', 'child', 'dependent', 'other'
    )),
    CONSTRAINT ck_family_member_name_lowercase CHECK (member_name = lower(member_name)),
    CONSTRAINT ck_family_owner_lowercase CHECK (owner = lower(owner)),
    CONSTRAINT ck_family_member_name_not_empty CHECK (length(trim(member_name)) > 0),
    CONSTRAINT ck_family_owner_not_empty CHECK (length(trim(owner)) > 0),
    CONSTRAINT ck_ssn_last_four_format CHECK (ssn_last_four IS NULL OR (ssn_last_four ~ '^[0-9]{4}$')),
    CONSTRAINT ck_insurance_member_id_length CHECK (insurance_member_id IS NULL OR length(insurance_member_id) <= 50),
    CONSTRAINT ck_medical_record_number_length CHECK (medical_record_number IS NULL OR length(medical_record_number) <= 50)
);

-- Unique constraint for owner + member_name combination
ALTER TABLE public.t_family_member
ADD CONSTRAINT uk_family_member_owner_name UNIQUE (owner, member_name);

-- Indexes for performance
CREATE INDEX idx_family_member_owner ON public.t_family_member(owner);
CREATE INDEX idx_family_member_relationship ON public.t_family_member(owner, relationship);
CREATE INDEX idx_family_member_active ON public.t_family_member(active_status, owner) WHERE active_status = true;
CREATE INDEX idx_family_member_insurance ON public.t_family_member(insurance_member_id) WHERE insurance_member_id IS NOT NULL;

-- Insert default family member for existing owners (self)
-- This ensures existing medical expenses can be attributed to the primary account holder
INSERT INTO public.t_family_member (owner, member_name, relationship)
SELECT DISTINCT account_name_owner, account_name_owner, 'self'
FROM public.t_account
WHERE active_status = true
AND account_name_owner NOT IN (
    SELECT owner FROM public.t_family_member WHERE relationship = 'self'
);-- Medical Expense Table Creation for Production Environment
-- Links medical expenses to existing transactions with 1:1 relationship
-- Supports comprehensive medical expense tracking with family member support

CREATE TABLE IF NOT EXISTS public.t_medical_expense (
    medical_expense_id          BIGSERIAL PRIMARY KEY,
    transaction_id              BIGINT NOT NULL,
    provider_id                 BIGINT,
    family_member_id            BIGINT,

    -- Core medical expense data
    service_date                DATE NOT NULL,
    service_description         TEXT,
    procedure_code              TEXT, -- CPT/HCPCS codes
    diagnosis_code              TEXT, -- ICD-10 codes

    -- Financial breakdown
    billed_amount              NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    insurance_discount         NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    insurance_paid             NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    patient_responsibility     NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    paid_date                  DATE,

    -- Insurance details
    is_out_of_network          BOOLEAN DEFAULT FALSE NOT NULL,
    claim_number               TEXT,
    claim_status               TEXT DEFAULT 'submitted' NOT NULL,

    -- Audit fields
    active_status              BOOLEAN DEFAULT TRUE NOT NULL,
    date_added                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated               TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- Constraints
    CONSTRAINT fk_medical_expense_transaction FOREIGN KEY (transaction_id)
        REFERENCES public.t_transaction(transaction_id) ON DELETE CASCADE,
    CONSTRAINT fk_medical_expense_provider FOREIGN KEY (provider_id)
        REFERENCES public.t_medical_provider(provider_id),
    CONSTRAINT fk_medical_expense_family_member FOREIGN KEY (family_member_id)
        REFERENCES public.t_family_member(family_member_id),
    CONSTRAINT uk_medical_expense_transaction UNIQUE (transaction_id),
    CONSTRAINT ck_medical_expense_claim_status CHECK (claim_status IN (
        'submitted', 'processing', 'approved', 'denied', 'paid', 'closed'
    )),
    CONSTRAINT ck_medical_expense_financial_amounts CHECK (
        billed_amount >= 0 AND
        insurance_discount >= 0 AND
        insurance_paid >= 0 AND
        patient_responsibility >= 0
    ),
    CONSTRAINT ck_medical_expense_service_date_valid CHECK (service_date <= CURRENT_DATE),
    CONSTRAINT ck_medical_expense_financial_consistency CHECK (
        billed_amount >= (insurance_discount + insurance_paid + patient_responsibility)
    )
);

-- Performance indexes
CREATE UNIQUE INDEX idx_medical_expense_transaction ON public.t_medical_expense(transaction_id);
CREATE INDEX idx_medical_expense_provider ON public.t_medical_expense(provider_id);
CREATE INDEX idx_medical_expense_family_member ON public.t_medical_expense(family_member_id);
CREATE INDEX idx_medical_expense_service_date ON public.t_medical_expense(service_date);
CREATE INDEX idx_medical_expense_claim_number ON public.t_medical_expense(claim_number) WHERE claim_number IS NOT NULL;
CREATE INDEX idx_medical_expense_claim_status ON public.t_medical_expense(claim_status);
CREATE INDEX idx_medical_expense_active ON public.t_medical_expense(active_status, service_date);

-- Comments for documentation
COMMENT ON TABLE public.t_medical_expense IS 'Medical expenses linked to transactions with comprehensive tracking';
COMMENT ON COLUMN public.t_medical_expense.medical_expense_id IS 'Primary key for medical expense records';
COMMENT ON COLUMN public.t_medical_expense.transaction_id IS 'Foreign key to t_transaction (1:1 relationship)';
COMMENT ON COLUMN public.t_medical_expense.provider_id IS 'Foreign key to t_medical_provider';
COMMENT ON COLUMN public.t_medical_expense.family_member_id IS 'Foreign key to t_family_member for tracking which family member';
COMMENT ON COLUMN public.t_medical_expense.service_date IS 'Date medical service was provided (different from payment date)';
COMMENT ON COLUMN public.t_medical_expense.billed_amount IS 'Original amount billed by provider';
COMMENT ON COLUMN public.t_medical_expense.insurance_discount IS 'Insurance negotiated discount amount';
COMMENT ON COLUMN public.t_medical_expense.insurance_paid IS 'Amount paid by insurance';
COMMENT ON COLUMN public.t_medical_expense.patient_responsibility IS 'Amount patient is responsible to pay';
COMMENT ON COLUMN public.t_medical_expense.is_out_of_network IS 'Whether provider is out of insurance network';
COMMENT ON COLUMN public.t_medical_expense.claim_status IS 'Status of insurance claim processing';-- Migration: V11__decouple-medical-expense-payments.sql
-- Purpose: Decouple medical expenses from transaction creation
-- Changes:
--   1. Make transaction_id nullable in t_medical_expense
--   2. Add paid_amount field to track actual payment amounts
--   3. Update existing records to sync paid_amount with patient_responsibility

-- Make transaction_id nullable to allow medical expenses without payments
ALTER TABLE public.t_medical_expense
ALTER COLUMN transaction_id DROP NOT NULL;

-- Add paid_amount field to track actual payment amounts
ALTER TABLE public.t_medical_expense
ADD COLUMN paid_amount NUMERIC(12,2) DEFAULT 0.00 NOT NULL;

-- Add constraint to ensure paid_amount is non-negative
ALTER TABLE public.t_medical_expense
ADD CONSTRAINT ck_paid_amount_non_negative CHECK (paid_amount >= 0);

-- Update existing records to sync paid_amount with patient_responsibility where transaction exists
-- This maintains backward compatibility for existing medical expenses with transactions
UPDATE public.t_medical_expense
SET paid_amount = patient_responsibility
WHERE transaction_id IS NOT NULL;

-- Add comment to document the new field
COMMENT ON COLUMN public.t_medical_expense.paid_amount IS 'Actual amount paid by patient, synced with linked transaction amount';
COMMENT ON COLUMN public.t_medical_expense.transaction_id IS 'Optional reference to payment transaction, can be null for unpaid expenses';-- Performance index for transaction account lookup
-- Migration: V12__add-transaction-account-lookup-index.sql
-- Purpose: Optimize findByAccountNameOwnerAndActiveStatusOrderByTransactionDateDesc query
-- Performance Impact: ~11,500ms → ~50-200ms expected improvement

SET client_min_messages TO WARNING;

-- ================================
-- TRANSACTION ACCOUNT LOOKUP INDEX
-- ================================

-- This index optimizes the most common transaction query pattern:
-- SELECT * FROM t_transaction
-- WHERE account_name_owner = ? AND active_status = true
-- ORDER BY transaction_date DESC

-- Index definition:
-- - account_name_owner: Primary filter column (high selectivity)
-- - active_status: Secondary filter (most queries use active_status = true)
-- - transaction_date DESC: Matches ORDER BY clause for index-only scan

DO $$
BEGIN
    -- Check if index already exists
    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
        AND tablename = 't_transaction'
        AND indexname = 'idx_transaction_account_lookup'
    ) THEN
        -- Create index
        CREATE INDEX idx_transaction_account_lookup
        ON t_transaction (account_name_owner, active_status, transaction_date DESC);

        RAISE NOTICE 'Created index: idx_transaction_account_lookup';
    ELSE
        RAISE NOTICE 'Index idx_transaction_account_lookup already exists, skipping';
    END IF;
END
$$;

-- Index statistics
-- Expected impact:
-- - Query execution time: 11,500ms → 50-200ms
-- - Eliminates full table scan
-- - Enables index-only scan for ORDER BY
-- - Disk space: ~50-100MB (depending on row count)
-- Multi-Tenant Stage 1: Database-only migration
-- Backfill owner columns, add owner to t_medical_expense,
-- add owner indexes, add composite unique constraints alongside existing ones.
-- Zero impact on running application since it ignores owner columns.

BEGIN;

---------------------------------------
-- 1. Backfill owner columns with 'henninb'
---------------------------------------
UPDATE public.t_account SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_transaction SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_category SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_description SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_payment SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_transfer SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_validation_amount SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_receipt_image SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_pending_transaction SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_parameter SET owner = 'henninb' WHERE owner IS NULL;
UPDATE public.t_transaction_categories SET owner = 'henninb' WHERE owner IS NULL;

---------------------------------------
-- 2. Add owner column to t_medical_expense
---------------------------------------
ALTER TABLE public.t_medical_expense ADD COLUMN IF NOT EXISTS owner TEXT NULL;
UPDATE public.t_medical_expense SET owner = 'henninb' WHERE owner IS NULL;

---------------------------------------
-- 3. Add indexes on owner
---------------------------------------
CREATE INDEX IF NOT EXISTS idx_account_owner ON public.t_account(owner);
CREATE INDEX IF NOT EXISTS idx_transaction_owner ON public.t_transaction(owner);
CREATE INDEX IF NOT EXISTS idx_category_owner ON public.t_category(owner);
CREATE INDEX IF NOT EXISTS idx_description_owner ON public.t_description(owner);
CREATE INDEX IF NOT EXISTS idx_payment_owner ON public.t_payment(owner);
CREATE INDEX IF NOT EXISTS idx_transfer_owner ON public.t_transfer(owner);
CREATE INDEX IF NOT EXISTS idx_validation_amount_owner ON public.t_validation_amount(owner);
CREATE INDEX IF NOT EXISTS idx_receipt_image_owner ON public.t_receipt_image(owner);
CREATE INDEX IF NOT EXISTS idx_pending_transaction_owner ON public.t_pending_transaction(owner);
CREATE INDEX IF NOT EXISTS idx_parameter_owner ON public.t_parameter(owner);
CREATE INDEX IF NOT EXISTS idx_transaction_categories_owner ON public.t_transaction_categories(owner);
CREATE INDEX IF NOT EXISTS idx_medical_expense_owner ON public.t_medical_expense(owner);

---------------------------------------
-- 4. Add composite unique constraints alongside existing ones
---------------------------------------

-- t_account: existing unique_account_name_owner_account_type(account_name_owner, account_type)
ALTER TABLE public.t_account
    ADD CONSTRAINT unique_owner_account_name_owner_account_type UNIQUE (owner, account_name_owner, account_type);

-- t_category: existing category_name UNIQUE
ALTER TABLE public.t_category
    ADD CONSTRAINT unique_owner_category_name UNIQUE (owner, category_name);

-- t_description: existing description_name UNIQUE
ALTER TABLE public.t_description
    ADD CONSTRAINT unique_owner_description_name UNIQUE (owner, description_name);

-- t_transaction: existing transaction_constraint(account_name_owner, transaction_date, description, category, amount, notes)
ALTER TABLE public.t_transaction
    ADD CONSTRAINT unique_owner_transaction UNIQUE (owner, account_name_owner, transaction_date, description, category, amount, notes);

-- t_payment: existing payment_constraint_destination(destination_account, transaction_date, amount) from V05
ALTER TABLE public.t_payment
    ADD CONSTRAINT unique_owner_payment UNIQUE (owner, destination_account, transaction_date, amount);

-- t_transfer: existing transfer_constraint(source_account, destination_account, transaction_date, amount)
ALTER TABLE public.t_transfer
    ADD CONSTRAINT unique_owner_transfer UNIQUE (owner, source_account, destination_account, transaction_date, amount);

-- t_parameter: existing parameter_name UNIQUE
ALTER TABLE public.t_parameter
    ADD CONSTRAINT unique_owner_parameter_name UNIQUE (owner, parameter_name);

-- t_pending_transaction: existing unique_pending_transaction_fields(account_name_owner, transaction_date, description, amount)
ALTER TABLE public.t_pending_transaction
    ADD CONSTRAINT unique_owner_pending_transaction UNIQUE (owner, account_name_owner, transaction_date, description, amount);

COMMIT;
-- Fix owner values to match JWT username (email) instead of short username.
-- V13 backfilled owner as 'henninb' but the JWT token uses the full username
-- from t_user (e.g. 'henninb@gmail.com'), causing a mismatch at runtime.

BEGIN;

UPDATE public.t_account SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_transaction SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_category SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_description SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_payment SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_transfer SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_validation_amount SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_receipt_image SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_pending_transaction SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_parameter SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_transaction_categories SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';
UPDATE public.t_medical_expense SET owner = 'henninb@gmail.com' WHERE owner = 'henninb';

COMMIT;
-- Multi-Tenant Stage 2: Enforce owner at database level
-- 1. Make owner NOT NULL on all tables
-- 2. Add compound unique constraints needed for new FKs
-- 3. Replace single-column FKs with compound (owner, ...) FKs
-- 4. Drop old global unique constraints (allows same names across tenants)
-- 5. Update stored functions to include owner parameter

BEGIN;

---------------------------------------
-- 1. Make owner NOT NULL on all tables
---------------------------------------
ALTER TABLE public.t_account ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_transaction ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_category ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_description ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_payment ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_transfer ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_validation_amount ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_receipt_image ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_pending_transaction ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_parameter ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_transaction_categories ALTER COLUMN owner SET NOT NULL;
ALTER TABLE public.t_medical_expense ALTER COLUMN owner SET NOT NULL;

-----------------------------------------------
-- 2. Add compound unique constraints for FKs
-----------------------------------------------
-- t_account needs (owner, account_name_owner) for FKs from payment, transfer, pending_transaction
ALTER TABLE public.t_account
    ADD CONSTRAINT unique_owner_account_name_owner UNIQUE (owner, account_name_owner);

-- t_account needs (owner, account_id, account_name_owner, account_type) for FK from transaction
ALTER TABLE public.t_account
    ADD CONSTRAINT unique_owner_account_id_name_type UNIQUE (owner, account_id, account_name_owner, account_type);

-----------------------------------------------
-- 3. Replace FKs with compound (owner, ...) FKs
-----------------------------------------------

-- t_transaction -> t_category: (owner, category) -> (owner, category_name)
ALTER TABLE public.t_transaction DROP CONSTRAINT fk_category_name;
ALTER TABLE public.t_transaction
    ADD CONSTRAINT fk_category_name FOREIGN KEY (owner, category)
        REFERENCES public.t_category (owner, category_name) ON UPDATE CASCADE ON DELETE RESTRICT;

-- t_transaction -> t_description: (owner, description) -> (owner, description_name)
ALTER TABLE public.t_transaction DROP CONSTRAINT fk_description_name;
ALTER TABLE public.t_transaction
    ADD CONSTRAINT fk_description_name FOREIGN KEY (owner, description)
        REFERENCES public.t_description (owner, description_name) ON UPDATE CASCADE ON DELETE RESTRICT;

-- t_transaction -> t_account: add owner to the compound FK
ALTER TABLE public.t_transaction DROP CONSTRAINT fk_account_id_account_name_owner;
ALTER TABLE public.t_transaction
    ADD CONSTRAINT fk_account_id_account_name_owner FOREIGN KEY (owner, account_id, account_name_owner, account_type)
        REFERENCES public.t_account (owner, account_id, account_name_owner, account_type) ON UPDATE CASCADE;

-- t_pending_transaction -> t_account: (owner, account_name_owner) -> (owner, account_name_owner)
ALTER TABLE public.t_pending_transaction DROP CONSTRAINT fk_pending_account;
ALTER TABLE public.t_pending_transaction
    ADD CONSTRAINT fk_pending_account FOREIGN KEY (owner, account_name_owner)
        REFERENCES public.t_account (owner, account_name_owner) ON UPDATE CASCADE;

-- t_payment -> t_account: source and destination compound FKs
ALTER TABLE public.t_payment DROP CONSTRAINT fk_payment_source_account;
ALTER TABLE public.t_payment
    ADD CONSTRAINT fk_payment_source_account FOREIGN KEY (owner, source_account)
        REFERENCES public.t_account (owner, account_name_owner) ON UPDATE CASCADE;

ALTER TABLE public.t_payment DROP CONSTRAINT fk_payment_destination_account;
ALTER TABLE public.t_payment
    ADD CONSTRAINT fk_payment_destination_account FOREIGN KEY (owner, destination_account)
        REFERENCES public.t_account (owner, account_name_owner) ON UPDATE CASCADE;

-- t_transfer -> t_account: source and destination compound FKs
ALTER TABLE public.t_transfer DROP CONSTRAINT fk_source_account;
ALTER TABLE public.t_transfer
    ADD CONSTRAINT fk_source_account FOREIGN KEY (owner, source_account)
        REFERENCES public.t_account (owner, account_name_owner) ON UPDATE CASCADE;

ALTER TABLE public.t_transfer DROP CONSTRAINT fk_destination_account;
ALTER TABLE public.t_transfer
    ADD CONSTRAINT fk_destination_account FOREIGN KEY (owner, destination_account)
        REFERENCES public.t_account (owner, account_name_owner) ON UPDATE CASCADE;

-----------------------------------------------
-- 4. Drop old global unique constraints
-----------------------------------------------
-- These prevented the same name from existing across different tenants.
-- The new owner-scoped constraints from V13 replace them.

-- t_account: drop global uniques (account_name_owner alone, and without owner)
ALTER TABLE public.t_account DROP CONSTRAINT t_account_account_name_owner_key;
ALTER TABLE public.t_account DROP CONSTRAINT unique_account_name_owner_account_type;
ALTER TABLE public.t_account DROP CONSTRAINT unique_account_name_owner_account_id;

-- t_category: drop global unique on category_name
ALTER TABLE public.t_category DROP CONSTRAINT t_category_category_name_key;

-- t_description: drop global unique on description_name
ALTER TABLE public.t_description DROP CONSTRAINT t_description_description_name_key;

-- t_transaction: drop global unique constraint
ALTER TABLE public.t_transaction DROP CONSTRAINT transaction_constraint;

-- t_payment: drop global unique constraint (from V05)
ALTER TABLE public.t_payment DROP CONSTRAINT payment_constraint_destination;

-- t_transfer: drop global unique constraint
ALTER TABLE public.t_transfer DROP CONSTRAINT transfer_constraint;

-- t_parameter: drop global unique on parameter_name
ALTER TABLE public.t_parameter DROP CONSTRAINT t_parameter_parameter_name_key;

-- t_pending_transaction: drop global unique constraint
ALTER TABLE public.t_pending_transaction DROP CONSTRAINT unique_pending_transaction_fields;

-----------------------------------------------
-- 5. Update stored functions with owner param
-----------------------------------------------
CREATE OR REPLACE FUNCTION rename_account_owner(
    p_old_name VARCHAR,
    p_new_name VARCHAR,
    p_owner VARCHAR
)
RETURNS VOID
SET SCHEMA 'public'
LANGUAGE PLPGSQL
AS
$$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET account_name_owner = $1 WHERE account_name_owner = $2 AND owner = $3'
    USING p_new_name, p_old_name, p_owner;

    EXECUTE 'UPDATE t_account SET account_name_owner = $1 WHERE account_name_owner = $2 AND owner = $3'
    USING p_new_name, p_old_name, p_owner;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$$;

CREATE OR REPLACE FUNCTION disable_account_owner(
    p_new_name VARCHAR,
    p_owner VARCHAR
)
RETURNS VOID
SET SCHEMA 'public'
LANGUAGE PLPGSQL
AS
$$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET active_status = false WHERE account_name_owner = $1 AND owner = $2'
    USING p_new_name, p_owner;

    EXECUTE 'UPDATE t_account SET active_status = false WHERE account_name_owner = $1 AND owner = $2'
    USING p_new_name, p_owner;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$$;

COMMIT;
-- Add compound (owner, ...) FKs for t_validation_amount and t_receipt_image
-- to prevent cross-tenant references via account_id and transaction_id.

BEGIN;

-----------------------------------------------
-- 1. Add unique constraints needed for compound FKs
-----------------------------------------------
ALTER TABLE public.t_account
    ADD CONSTRAINT unique_owner_account_id UNIQUE (owner, account_id);

ALTER TABLE public.t_transaction
    ADD CONSTRAINT unique_owner_transaction_id UNIQUE (owner, transaction_id);

-----------------------------------------------
-- 2. Replace FKs with compound (owner, ...) FKs
-----------------------------------------------

-- t_validation_amount -> t_account: (owner, account_id) -> (owner, account_id)
ALTER TABLE public.t_validation_amount DROP CONSTRAINT fk_account_id;
ALTER TABLE public.t_validation_amount
    ADD CONSTRAINT fk_account_id FOREIGN KEY (owner, account_id)
        REFERENCES public.t_account (owner, account_id) ON UPDATE CASCADE;

-- t_receipt_image -> t_transaction: (owner, transaction_id) -> (owner, transaction_id)
ALTER TABLE public.t_receipt_image DROP CONSTRAINT fk_transaction;
ALTER TABLE public.t_receipt_image
    ADD CONSTRAINT fk_transaction FOREIGN KEY (owner, transaction_id)
        REFERENCES public.t_transaction (owner, transaction_id) ON UPDATE CASCADE;

COMMIT;
-- Fix t_family_member multi-tenant gap:
-- 1. V09 seed data set owner to account_name_owner values (account names, not username)
-- 2. V14 fixed owner from 'henninb' to 'henninb@gmail.com' but missed t_family_member
-- 3. t_medical_expense FKs to t_family_member and t_transaction are single-column (no tenant isolation)

BEGIN;

-----------------------------------------------
-- 1. Fix owner values in t_family_member
--    V09 used account_name_owner as owner, which is wrong for multi-tenancy.
--    All existing family members belong to the only existing user.
-----------------------------------------------
UPDATE public.t_family_member
SET owner = 'henninb@gmail.com'
WHERE owner IS NULL OR owner = '' OR owner != 'henninb@gmail.com';

-----------------------------------------------
-- 2. Add unique constraint on (owner, family_member_id) for compound FK target
-----------------------------------------------
ALTER TABLE public.t_family_member
    ADD CONSTRAINT unique_owner_family_member_id UNIQUE (owner, family_member_id);

-----------------------------------------------
-- 3. Replace single-column FK on t_medical_expense -> t_family_member
--    with compound (owner, family_member_id) FK
-----------------------------------------------
ALTER TABLE public.t_medical_expense DROP CONSTRAINT fk_medical_expense_family_member;
ALTER TABLE public.t_medical_expense
    ADD CONSTRAINT fk_medical_expense_family_member FOREIGN KEY (owner, family_member_id)
        REFERENCES public.t_family_member (owner, family_member_id) ON UPDATE CASCADE;

-----------------------------------------------
-- 4. Replace single-column FK on t_medical_expense -> t_transaction
--    with compound (owner, transaction_id) FK
--    (V16 added unique_owner_transaction_id on t_transaction but only
--     updated t_receipt_image, not t_medical_expense)
-----------------------------------------------
ALTER TABLE public.t_medical_expense DROP CONSTRAINT fk_medical_expense_transaction;
ALTER TABLE public.t_medical_expense
    ADD CONSTRAINT fk_medical_expense_transaction FOREIGN KEY (owner, transaction_id)
        REFERENCES public.t_transaction (owner, transaction_id) ON DELETE CASCADE;

COMMIT;
-- Fix t_transaction_categories owner: Hibernate's @ManyToMany @JoinTable only
-- inserts (transaction_id, category_id), leaving owner NULL.
-- Update the existing BEFORE INSERT trigger to auto-populate owner from t_transaction.

CREATE OR REPLACE FUNCTION fn_insert_transaction_categories()
    RETURNS TRIGGER
    SET SCHEMA 'public'
    LANGUAGE PLPGSQL
AS
$$
    BEGIN
      NEW.owner := (SELECT owner FROM t_transaction WHERE transaction_id = NEW.transaction_id);
      NEW.date_updated := CURRENT_TIMESTAMP;
      NEW.date_added := CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
$$;
