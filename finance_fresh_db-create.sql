-- finance_fresh_db-create.sql
-- Schema DDL for finance_fresh_db, generated from the live finance_db schema
-- (pg_dump -s --no-owner) plus the seed rows at the bottom.
--
-- Run against the postgres database (it drops and recreates finance_fresh_db):
--   psql -X -v ON_ERROR_STOP=1 -U henninb -d postgres -f finance_fresh_db-create.sql
--
-- run-backup.py applies this file and then imports data into it, and it refuses
-- to continue if a table's columns differ from the source database. When the
-- live schema changes, regenerate the section between BEGIN and COMMIT with:
--   pg_dump -s --no-owner -d finance_db
-- The explicit BEGIN/COMMIT keeps this file safe under AUTOCOMMIT off.

DROP DATABASE IF EXISTS finance_fresh_db;
CREATE DATABASE finance_fresh_db;
GRANT ALL PRIVILEGES ON DATABASE finance_fresh_db TO henninb;

REVOKE CONNECT ON DATABASE finance_fresh_db FROM public;

\connect finance_fresh_db

BEGIN;

--
-- PostgreSQL database dump
--


-- Dumped from database version 18.4 (Debian 18.4-1.pgdg13+1)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: prod; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA prod;


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: disable_account_owner(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.disable_account_owner(p_new_name character varying) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET active_status = false WHERE account_name_owner = $1'
    USING p_new_name;

    EXECUTE 'UPDATE t_account SET active_status = false WHERE account_name_owner = $1'
    USING p_new_name;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$_$;


--
-- Name: disable_account_owner(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.disable_account_owner(p_new_name character varying, p_owner character varying) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET active_status = false WHERE account_name_owner = $1 AND owner = $2'
    USING p_new_name, p_owner;

    EXECUTE 'UPDATE t_account SET active_status = false WHERE account_name_owner = $1 AND owner = $2'
    USING p_new_name, p_owner;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$_$;


--
-- Name: fn_insert_transaction_categories(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_insert_transaction_categories() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
    BEGIN
      NEW.owner := (SELECT owner FROM t_transaction WHERE transaction_id = NEW.transaction_id);
      NEW.date_updated := CURRENT_TIMESTAMP;
      NEW.date_added := CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
$$;


--
-- Name: fn_update_transaction_categories(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_update_transaction_categories() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
    BEGIN
      NEW.date_updated := CURRENT_TIMESTAMP;
      RETURN NEW;
    END;
$$;


--
-- Name: rename_account_owner(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rename_account_owner(p_old_name character varying, p_new_name character varying) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET account_name_owner = $1 WHERE account_name_owner = $2'
    USING p_new_name, p_old_name;

    EXECUTE 'UPDATE t_account SET account_name_owner = $1 WHERE account_name_owner = $2'
    USING p_new_name, p_old_name;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$_$;


--
-- Name: rename_account_owner(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rename_account_owner(p_old_name character varying, p_new_name character varying, p_owner character varying) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $_$
BEGIN
    EXECUTE 'ALTER TABLE t_transaction DISABLE TRIGGER ALL';

    EXECUTE 'UPDATE t_transaction SET account_name_owner = $1 WHERE account_name_owner = $2 AND owner = $3'
    USING p_new_name, p_old_name, p_owner;

    EXECUTE 'UPDATE t_account SET account_name_owner = $1 WHERE account_name_owner = $2 AND owner = $3'
    USING p_new_name, p_old_name, p_owner;

    EXECUTE 'ALTER TABLE t_transaction ENABLE TRIGGER ALL';
END;
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


--
-- Name: t_account; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_account (
    account_id bigint NOT NULL,
    account_name_owner text NOT NULL,
    account_name text,
    account_owner text,
    account_type text DEFAULT 'unknown'::text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    payment_required boolean DEFAULT true,
    moniker text DEFAULT '0000'::text NOT NULL,
    future numeric(12,2) DEFAULT 0.00,
    outstanding numeric(12,2) DEFAULT 0.00,
    cleared numeric(12,2) DEFAULT 0.00,
    date_closed timestamp without time zone,
    owner text NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    validation_date timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    billing_statement_close_day smallint,
    billing_grace_period_days smallint,
    billing_due_day_same_month smallint,
    billing_due_day_next_month smallint,
    billing_cycle_weekend_shift text,
    tax_bucket text,
    CONSTRAINT ck_account_type CHECK ((account_type = ANY (ARRAY['credit'::text, 'debit'::text, 'undefined'::text, 'checking'::text, 'savings'::text, 'credit_card'::text, 'certificate'::text, 'money_market'::text, 'brokerage'::text, 'retirement_401k'::text, 'retirement_ira'::text, 'retirement_roth'::text, 'pension'::text, 'hsa'::text, 'fsa'::text, 'medical_savings'::text, 'mortgage'::text, 'auto_loan'::text, 'student_loan'::text, 'personal_loan'::text, 'line_of_credit'::text, 'utility'::text, 'prepaid'::text, 'gift_card'::text, 'business_checking'::text, 'business_savings'::text, 'business_credit'::text, 'cash'::text, 'escrow'::text, 'trust'::text]))),
    CONSTRAINT ck_account_type_lowercase CHECK ((account_type = lower(account_type))),
    CONSTRAINT ck_billing_cycle_weekend_shift CHECK ((billing_cycle_weekend_shift = ANY (ARRAY['back'::text, 'forward'::text, 'back_sat_only'::text]))),
    CONSTRAINT ck_billing_due_day_next_month CHECK (((billing_due_day_next_month >= 1) AND (billing_due_day_next_month <= 31))),
    CONSTRAINT ck_billing_due_day_same_month CHECK (((billing_due_day_same_month >= 1) AND (billing_due_day_same_month <= 31))),
    CONSTRAINT ck_billing_due_method_exclusive CHECK ((((
CASE
    WHEN (billing_grace_period_days IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (billing_due_day_same_month IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (billing_due_day_next_month IS NOT NULL) THEN 1
    ELSE 0
END) <= 1)),
    CONSTRAINT ck_billing_grace_period_days CHECK (((billing_grace_period_days >= 1) AND (billing_grace_period_days <= 60))),
    CONSTRAINT ck_billing_statement_close_day CHECK (((billing_statement_close_day >= 1) AND (billing_statement_close_day <= 31))),
    CONSTRAINT ck_tax_bucket CHECK ((tax_bucket = ANY (ARRAY['pretax'::text, 'taxable'::text, 'roth'::text])))
);


--
-- Name: t_account_account_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_account_account_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_account_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_account_account_id_seq OWNED BY public.t_account.account_id;


--
-- Name: t_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_category (
    category_id bigint NOT NULL,
    category_name text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    CONSTRAINT ck_lowercase_category CHECK ((category_name = lower(category_name)))
);


--
-- Name: t_category_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_category_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_category_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_category_category_id_seq OWNED BY public.t_category.category_id;


--
-- Name: t_description; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_description (
    description_id bigint NOT NULL,
    description_name text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    CONSTRAINT t_description_description_lowercase_ck CHECK ((description_name = lower(description_name)))
);


--
-- Name: t_description_description_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_description_description_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_description_description_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_description_description_id_seq OWNED BY public.t_description.description_id;


--
-- Name: t_family_member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_family_member (
    family_member_id bigint NOT NULL,
    owner text NOT NULL,
    member_name text NOT NULL,
    relationship text DEFAULT 'self'::text NOT NULL,
    date_of_birth date,
    insurance_member_id text,
    ssn_last_four text,
    medical_record_number text,
    active_status boolean DEFAULT true NOT NULL,
    date_added timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_family_member_name_lowercase CHECK ((member_name = lower(member_name))),
    CONSTRAINT ck_family_member_name_not_empty CHECK ((length(TRIM(BOTH FROM member_name)) > 0)),
    CONSTRAINT ck_family_owner_lowercase CHECK ((owner = lower(owner))),
    CONSTRAINT ck_family_owner_not_empty CHECK ((length(TRIM(BOTH FROM owner)) > 0)),
    CONSTRAINT ck_family_relationship CHECK ((relationship = ANY (ARRAY['self'::text, 'spouse'::text, 'child'::text, 'dependent'::text, 'other'::text]))),
    CONSTRAINT ck_insurance_member_id_length CHECK (((insurance_member_id IS NULL) OR (length(insurance_member_id) <= 50))),
    CONSTRAINT ck_medical_record_number_length CHECK (((medical_record_number IS NULL) OR (length(medical_record_number) <= 50))),
    CONSTRAINT ck_ssn_last_four_format CHECK (((ssn_last_four IS NULL) OR (ssn_last_four ~ '^[0-9]{4}$'::text)))
);


--
-- Name: t_family_member_family_member_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_family_member_family_member_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_family_member_family_member_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_family_member_family_member_id_seq OWNED BY public.t_family_member.family_member_id;


--
-- Name: t_medical_expense; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_medical_expense (
    medical_expense_id bigint NOT NULL,
    transaction_id bigint,
    provider_id bigint,
    family_member_id bigint,
    service_date date NOT NULL,
    service_description text,
    procedure_code text,
    diagnosis_code text,
    billed_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    insurance_discount numeric(12,2) DEFAULT 0.00 NOT NULL,
    insurance_paid numeric(12,2) DEFAULT 0.00 NOT NULL,
    patient_responsibility numeric(12,2) DEFAULT 0.00 NOT NULL,
    paid_date date,
    is_out_of_network boolean DEFAULT false NOT NULL,
    claim_number text,
    claim_status text DEFAULT 'submitted'::text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_added timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    paid_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    owner text NOT NULL,
    CONSTRAINT ck_medical_expense_claim_status CHECK ((claim_status = ANY (ARRAY['submitted'::text, 'processing'::text, 'approved'::text, 'denied'::text, 'paid'::text, 'closed'::text]))),
    CONSTRAINT ck_medical_expense_financial_amounts CHECK (((billed_amount >= (0)::numeric) AND (insurance_discount >= (0)::numeric) AND (insurance_paid >= (0)::numeric) AND (patient_responsibility >= (0)::numeric))),
    CONSTRAINT ck_medical_expense_financial_consistency CHECK ((billed_amount >= ((insurance_discount + insurance_paid) + patient_responsibility))),
    CONSTRAINT ck_medical_expense_service_date_valid CHECK ((service_date <= CURRENT_DATE)),
    CONSTRAINT ck_paid_amount_non_negative CHECK ((paid_amount >= (0)::numeric))
);


--
-- Name: TABLE t_medical_expense; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.t_medical_expense IS 'Medical expenses linked to transactions with comprehensive tracking';


--
-- Name: COLUMN t_medical_expense.medical_expense_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.medical_expense_id IS 'Primary key for medical expense records';


--
-- Name: COLUMN t_medical_expense.transaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.transaction_id IS 'Optional reference to payment transaction, can be null for unpaid expenses';


--
-- Name: COLUMN t_medical_expense.provider_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.provider_id IS 'Foreign key to t_medical_provider';


--
-- Name: COLUMN t_medical_expense.family_member_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.family_member_id IS 'Foreign key to t_family_member for tracking which family member';


--
-- Name: COLUMN t_medical_expense.service_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.service_date IS 'Date medical service was provided (different from payment date)';


--
-- Name: COLUMN t_medical_expense.billed_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.billed_amount IS 'Original amount billed by provider';


--
-- Name: COLUMN t_medical_expense.insurance_discount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.insurance_discount IS 'Insurance negotiated discount amount';


--
-- Name: COLUMN t_medical_expense.insurance_paid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.insurance_paid IS 'Amount paid by insurance';


--
-- Name: COLUMN t_medical_expense.patient_responsibility; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.patient_responsibility IS 'Amount patient is responsible to pay';


--
-- Name: COLUMN t_medical_expense.is_out_of_network; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.is_out_of_network IS 'Whether provider is out of insurance network';


--
-- Name: COLUMN t_medical_expense.claim_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.claim_status IS 'Status of insurance claim processing';


--
-- Name: COLUMN t_medical_expense.paid_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_medical_expense.paid_amount IS 'Actual amount paid by patient, synced with linked transaction amount';


--
-- Name: t_medical_expense_medical_expense_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_medical_expense_medical_expense_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_medical_expense_medical_expense_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_medical_expense_medical_expense_id_seq OWNED BY public.t_medical_expense.medical_expense_id;


--
-- Name: t_medical_provider; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_medical_provider (
    provider_id bigint NOT NULL,
    provider_name text NOT NULL,
    provider_type text DEFAULT 'general'::text NOT NULL,
    specialty text,
    npi text,
    tax_id text,
    address_line1 text,
    address_line2 text,
    city text,
    state text,
    zip_code text,
    country text DEFAULT 'US'::text,
    phone text,
    fax text,
    email text,
    website text,
    network_status text DEFAULT 'unknown'::text,
    billing_name text,
    notes text,
    active_status boolean DEFAULT true NOT NULL,
    date_added timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    date_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_network_status CHECK ((network_status = ANY (ARRAY['in_network'::text, 'out_of_network'::text, 'unknown'::text]))),
    CONSTRAINT ck_npi_format CHECK (((npi IS NULL) OR (npi ~ '^[0-9]{10}$'::text))),
    CONSTRAINT ck_phone_format CHECK (((phone IS NULL) OR (length(phone) >= 10))),
    CONSTRAINT ck_provider_name_lowercase CHECK ((provider_name = lower(provider_name))),
    CONSTRAINT ck_provider_name_not_empty CHECK ((length(TRIM(BOTH FROM provider_name)) > 0)),
    CONSTRAINT ck_provider_type CHECK ((provider_type = ANY (ARRAY['general'::text, 'specialist'::text, 'hospital'::text, 'pharmacy'::text, 'laboratory'::text, 'imaging'::text, 'urgent_care'::text, 'emergency'::text, 'mental_health'::text, 'dental'::text, 'vision'::text, 'physical_therapy'::text, 'other'::text]))),
    CONSTRAINT ck_zip_code_format CHECK (((zip_code IS NULL) OR (zip_code ~ '^[0-9]{5}(-[0-9]{4})?$'::text)))
);


--
-- Name: t_medical_provider_provider_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_medical_provider_provider_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_medical_provider_provider_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_medical_provider_provider_id_seq OWNED BY public.t_medical_provider.provider_id;


--
-- Name: t_parameter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_parameter (
    parameter_id bigint NOT NULL,
    parameter_name text NOT NULL,
    parameter_value text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL
);


--
-- Name: t_parameter_parameter_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_parameter_parameter_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_parameter_parameter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_parameter_parameter_id_seq OWNED BY public.t_parameter.parameter_id;


--
-- Name: t_payment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_payment (
    payment_id bigint NOT NULL,
    transaction_date date NOT NULL,
    amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    guid_source text NOT NULL,
    guid_destination text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    source_account text DEFAULT 'bcu-checking_brian'::text NOT NULL,
    destination_account text DEFAULT ''::text NOT NULL
);


--
-- Name: t_payment_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_payment_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_payment_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_payment_payment_id_seq OWNED BY public.t_payment.payment_id;


--
-- Name: t_receipt_image; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_receipt_image (
    receipt_image_id bigint NOT NULL,
    transaction_id bigint NOT NULL,
    image bytea NOT NULL,
    thumbnail bytea NOT NULL,
    image_format_type text DEFAULT 'undefined'::text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    CONSTRAINT ck_image_size CHECK ((length(image) <= 1048576)),
    CONSTRAINT ck_image_type CHECK ((image_format_type = ANY (ARRAY['jpeg'::text, 'png'::text, 'undefined'::text])))
);


--
-- Name: t_receipt_image_receipt_image_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_receipt_image_receipt_image_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_receipt_image_receipt_image_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_receipt_image_receipt_image_id_seq OWNED BY public.t_receipt_image.receipt_image_id;


--
-- Name: t_reward; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_reward (
    reward_id bigint NOT NULL,
    account_id bigint NOT NULL,
    owner text NOT NULL,
    multiplier numeric(4,1) NOT NULL,
    category text NOT NULL,
    cpp numeric(6,4) DEFAULT 0.01 NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_added timestamp without time zone DEFAULT now() NOT NULL,
    date_updated timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: t_reward_reward_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_reward_reward_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_reward_reward_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_reward_reward_id_seq OWNED BY public.t_reward.reward_id;


--
-- Name: t_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_role (
    role_id bigint NOT NULL,
    role text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    CONSTRAINT ck_lowercase_username CHECK ((role = lower(role)))
);


--
-- Name: t_role_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_role_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_role_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_role_role_id_seq OWNED BY public.t_role.role_id;


--
-- Name: t_token_blacklist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_token_blacklist (
    token_blacklist_id bigint NOT NULL,
    token_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE t_token_blacklist; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.t_token_blacklist IS 'Revoked JWT tokens (SHA-256 hash); enables logout revocation across restarts';


--
-- Name: COLUMN t_token_blacklist.token_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_token_blacklist.token_hash IS 'SHA-256 hex digest of the raw JWT — raw tokens are never stored';


--
-- Name: COLUMN t_token_blacklist.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.t_token_blacklist.expires_at IS 'Original token expiry; rows past this time can be pruned';


--
-- Name: t_token_blacklist_token_blacklist_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_token_blacklist_token_blacklist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_token_blacklist_token_blacklist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_token_blacklist_token_blacklist_id_seq OWNED BY public.t_token_blacklist.token_blacklist_id;


--
-- Name: t_transaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_transaction (
    transaction_id bigint NOT NULL,
    account_id bigint NOT NULL,
    account_type text DEFAULT 'undefined'::text NOT NULL,
    transaction_type text DEFAULT 'undefined'::text NOT NULL,
    account_name_owner text NOT NULL,
    guid text NOT NULL,
    transaction_date date NOT NULL,
    due_date date,
    description text NOT NULL,
    category text DEFAULT ''::text NOT NULL,
    amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    transaction_state text DEFAULT 'undefined'::text NOT NULL,
    reoccurring_type text DEFAULT 'undefined'::text,
    active_status boolean DEFAULT true NOT NULL,
    notes text DEFAULT ''::text NOT NULL,
    receipt_image_id bigint,
    owner text NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    CONSTRAINT ck_reoccurring_type CHECK ((reoccurring_type = ANY (ARRAY['annually'::text, 'biannually'::text, 'fortnightly'::text, 'monthly'::text, 'quarterly'::text, 'onetime'::text, 'undefined'::text]))),
    CONSTRAINT ck_transaction_account_type CHECK ((account_type = ANY (ARRAY['credit'::text, 'debit'::text, 'undefined'::text, 'checking'::text, 'savings'::text, 'credit_card'::text, 'certificate'::text, 'money_market'::text, 'brokerage'::text, 'retirement_401k'::text, 'retirement_ira'::text, 'retirement_roth'::text, 'pension'::text, 'hsa'::text, 'fsa'::text, 'medical_savings'::text, 'mortgage'::text, 'auto_loan'::text, 'student_loan'::text, 'personal_loan'::text, 'line_of_credit'::text, 'utility'::text, 'prepaid'::text, 'gift_card'::text, 'business_checking'::text, 'business_savings'::text, 'business_credit'::text, 'cash'::text, 'escrow'::text, 'trust'::text]))),
    CONSTRAINT ck_transaction_state CHECK ((transaction_state = ANY (ARRAY['outstanding'::text, 'future'::text, 'cleared'::text, 'undefined'::text]))),
    CONSTRAINT ck_transaction_type CHECK ((transaction_type = ANY (ARRAY['expense'::text, 'income'::text, 'transfer'::text, 'undefined'::text]))),
    CONSTRAINT t_transaction_category_lowercase_ck CHECK ((category = lower(category))),
    CONSTRAINT t_transaction_description_lowercase_ck CHECK ((description = lower(description))),
    CONSTRAINT t_transaction_notes_lowercase_ck CHECK ((notes = lower(notes)))
);


--
-- Name: t_transaction_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_transaction_categories (
    category_id bigint NOT NULL,
    transaction_id bigint NOT NULL,
    owner text NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL
);


--
-- Name: t_transaction_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_transaction_transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_transaction_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_transaction_transaction_id_seq OWNED BY public.t_transaction.transaction_id;


--
-- Name: t_transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_transfer (
    transfer_id bigint NOT NULL,
    source_account text NOT NULL,
    destination_account text NOT NULL,
    transaction_date date NOT NULL,
    amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    guid_source text NOT NULL,
    guid_destination text NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    version bigint DEFAULT 0 NOT NULL
);


--
-- Name: t_transfer_transfer_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_transfer_transfer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_transfer_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_transfer_transfer_id_seq OWNED BY public.t_transfer.transfer_id;


--
-- Name: t_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_user (
    user_id bigint NOT NULL,
    username text NOT NULL,
    password text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    date_added timestamp without time zone DEFAULT to_timestamp((0)::double precision) NOT NULL,
    first_name text DEFAULT 'none'::text NOT NULL,
    last_name text DEFAULT 'none'::text NOT NULL,
    CONSTRAINT ck_lowercase_username CHECK ((username = lower(username)))
);


--
-- Name: t_user_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_user_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_user_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_user_user_id_seq OWNED BY public.t_user.user_id;


--
-- Name: t_validation_amount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_validation_amount (
    validation_id bigint NOT NULL,
    account_id bigint NOT NULL,
    validation_date timestamp without time zone DEFAULT '1970-01-01 00:00:00+00'::timestamp with time zone NOT NULL,
    transaction_state text DEFAULT 'undefined'::text NOT NULL,
    amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    owner text NOT NULL,
    active_status boolean DEFAULT true NOT NULL,
    date_updated timestamp without time zone DEFAULT now() NOT NULL,
    date_added timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_transaction_state CHECK ((transaction_state = ANY (ARRAY['outstanding'::text, 'future'::text, 'cleared'::text, 'undefined'::text])))
);


--
-- Name: t_validation_amount_validation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_validation_amount_validation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_validation_amount_validation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_validation_amount_validation_id_seq OWNED BY public.t_validation_amount.validation_id;


--
-- Name: t_account account_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account ALTER COLUMN account_id SET DEFAULT nextval('public.t_account_account_id_seq'::regclass);


--
-- Name: t_category category_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_category ALTER COLUMN category_id SET DEFAULT nextval('public.t_category_category_id_seq'::regclass);


--
-- Name: t_description description_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_description ALTER COLUMN description_id SET DEFAULT nextval('public.t_description_description_id_seq'::regclass);


--
-- Name: t_family_member family_member_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_family_member ALTER COLUMN family_member_id SET DEFAULT nextval('public.t_family_member_family_member_id_seq'::regclass);


--
-- Name: t_medical_expense medical_expense_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense ALTER COLUMN medical_expense_id SET DEFAULT nextval('public.t_medical_expense_medical_expense_id_seq'::regclass);


--
-- Name: t_medical_provider provider_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_provider ALTER COLUMN provider_id SET DEFAULT nextval('public.t_medical_provider_provider_id_seq'::regclass);


--
-- Name: t_parameter parameter_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_parameter ALTER COLUMN parameter_id SET DEFAULT nextval('public.t_parameter_parameter_id_seq'::regclass);


--
-- Name: t_payment payment_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment ALTER COLUMN payment_id SET DEFAULT nextval('public.t_payment_payment_id_seq'::regclass);


--
-- Name: t_receipt_image receipt_image_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_receipt_image ALTER COLUMN receipt_image_id SET DEFAULT nextval('public.t_receipt_image_receipt_image_id_seq'::regclass);


--
-- Name: t_reward reward_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_reward ALTER COLUMN reward_id SET DEFAULT nextval('public.t_reward_reward_id_seq'::regclass);


--
-- Name: t_role role_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_role ALTER COLUMN role_id SET DEFAULT nextval('public.t_role_role_id_seq'::regclass);


--
-- Name: t_token_blacklist token_blacklist_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_token_blacklist ALTER COLUMN token_blacklist_id SET DEFAULT nextval('public.t_token_blacklist_token_blacklist_id_seq'::regclass);


--
-- Name: t_transaction transaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction ALTER COLUMN transaction_id SET DEFAULT nextval('public.t_transaction_transaction_id_seq'::regclass);


--
-- Name: t_transfer transfer_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer ALTER COLUMN transfer_id SET DEFAULT nextval('public.t_transfer_transfer_id_seq'::regclass);


--
-- Name: t_user user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_user ALTER COLUMN user_id SET DEFAULT nextval('public.t_user_user_id_seq'::regclass);


--
-- Name: t_validation_amount validation_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_validation_amount ALTER COLUMN validation_id SET DEFAULT nextval('public.t_validation_amount_validation_id_seq'::regclass);


--
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- Name: t_account t_account_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account
    ADD CONSTRAINT t_account_pkey PRIMARY KEY (account_id);


--
-- Name: t_category t_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_category
    ADD CONSTRAINT t_category_pkey PRIMARY KEY (category_id);


--
-- Name: t_description t_description_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_description
    ADD CONSTRAINT t_description_pkey PRIMARY KEY (description_id);


--
-- Name: t_family_member t_family_member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_family_member
    ADD CONSTRAINT t_family_member_pkey PRIMARY KEY (family_member_id);


--
-- Name: t_medical_expense t_medical_expense_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense
    ADD CONSTRAINT t_medical_expense_pkey PRIMARY KEY (medical_expense_id);


--
-- Name: t_medical_provider t_medical_provider_npi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_provider
    ADD CONSTRAINT t_medical_provider_npi_key UNIQUE (npi);


--
-- Name: t_medical_provider t_medical_provider_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_provider
    ADD CONSTRAINT t_medical_provider_pkey PRIMARY KEY (provider_id);


--
-- Name: t_parameter t_parameter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_parameter
    ADD CONSTRAINT t_parameter_pkey PRIMARY KEY (parameter_id);


--
-- Name: t_payment t_payment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT t_payment_pkey PRIMARY KEY (payment_id);


--
-- Name: t_receipt_image t_receipt_image_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_receipt_image
    ADD CONSTRAINT t_receipt_image_pkey PRIMARY KEY (receipt_image_id);


--
-- Name: t_reward t_reward_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_reward
    ADD CONSTRAINT t_reward_pkey PRIMARY KEY (reward_id);


--
-- Name: t_role t_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_role
    ADD CONSTRAINT t_role_pkey PRIMARY KEY (role_id);


--
-- Name: t_role t_role_role_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_role
    ADD CONSTRAINT t_role_role_key UNIQUE (role);


--
-- Name: t_token_blacklist t_token_blacklist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_token_blacklist
    ADD CONSTRAINT t_token_blacklist_pkey PRIMARY KEY (token_blacklist_id);


--
-- Name: t_transaction_categories t_transaction_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction_categories
    ADD CONSTRAINT t_transaction_categories_pkey PRIMARY KEY (category_id, transaction_id);


--
-- Name: t_transaction t_transaction_guid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT t_transaction_guid_key UNIQUE (guid);


--
-- Name: t_transaction t_transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT t_transaction_pkey PRIMARY KEY (transaction_id);


--
-- Name: t_transfer t_transfer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT t_transfer_pkey PRIMARY KEY (transfer_id);


--
-- Name: t_user t_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_user
    ADD CONSTRAINT t_user_pkey PRIMARY KEY (user_id);


--
-- Name: t_user t_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_user
    ADD CONSTRAINT t_user_username_key UNIQUE (username);


--
-- Name: t_validation_amount t_validation_amount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_validation_amount
    ADD CONSTRAINT t_validation_amount_pkey PRIMARY KEY (validation_id);


--
-- Name: t_family_member uk_family_member_owner_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_family_member
    ADD CONSTRAINT uk_family_member_owner_name UNIQUE (owner, member_name);


--
-- Name: t_medical_expense uk_medical_expense_transaction; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense
    ADD CONSTRAINT uk_medical_expense_transaction UNIQUE (transaction_id);


--
-- Name: t_reward uk_reward_account_multiplier_category; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_reward
    ADD CONSTRAINT uk_reward_account_multiplier_category UNIQUE (account_id, multiplier, category);


--
-- Name: t_token_blacklist uk_token_blacklist_token_hash; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_token_blacklist
    ADD CONSTRAINT uk_token_blacklist_token_hash UNIQUE (token_hash);


--
-- Name: t_account unique_owner_account_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account
    ADD CONSTRAINT unique_owner_account_id UNIQUE (owner, account_id);


--
-- Name: t_account unique_owner_account_id_name_type; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account
    ADD CONSTRAINT unique_owner_account_id_name_type UNIQUE (owner, account_id, account_name_owner, account_type);


--
-- Name: t_account unique_owner_account_name_owner; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account
    ADD CONSTRAINT unique_owner_account_name_owner UNIQUE (owner, account_name_owner);


--
-- Name: t_account unique_owner_account_name_owner_account_type; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_account
    ADD CONSTRAINT unique_owner_account_name_owner_account_type UNIQUE (owner, account_name_owner, account_type);


--
-- Name: t_category unique_owner_category_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_category
    ADD CONSTRAINT unique_owner_category_name UNIQUE (owner, category_name);


--
-- Name: t_description unique_owner_description_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_description
    ADD CONSTRAINT unique_owner_description_name UNIQUE (owner, description_name);


--
-- Name: t_family_member unique_owner_family_member_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_family_member
    ADD CONSTRAINT unique_owner_family_member_id UNIQUE (owner, family_member_id);


--
-- Name: t_parameter unique_owner_parameter_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_parameter
    ADD CONSTRAINT unique_owner_parameter_name UNIQUE (owner, parameter_name);


--
-- Name: t_payment unique_owner_payment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT unique_owner_payment UNIQUE (owner, source_account, destination_account, transaction_date, amount);


--
-- Name: t_transaction unique_owner_transaction; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT unique_owner_transaction UNIQUE (owner, account_name_owner, transaction_date, description, category, amount, notes);


--
-- Name: t_transaction unique_owner_transaction_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT unique_owner_transaction_id UNIQUE (owner, transaction_id);


--
-- Name: t_transfer unique_owner_transfer; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT unique_owner_transfer UNIQUE (owner, source_account, destination_account, transaction_date, amount);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: idx_account_active_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_active_status ON public.t_account USING btree (active_status) WHERE (active_status = true);


--
-- Name: idx_account_active_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_active_type ON public.t_account USING btree (active_status, account_type) WHERE (active_status = true);


--
-- Name: idx_account_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_owner ON public.t_account USING btree (owner);


--
-- Name: idx_account_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_type ON public.t_account USING btree (account_type);


--
-- Name: idx_category_active_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_category_active_status ON public.t_category USING btree (active_status) WHERE (active_status = true);


--
-- Name: idx_category_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_category_owner ON public.t_category USING btree (owner);


--
-- Name: idx_description_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_description_owner ON public.t_description USING btree (owner);


--
-- Name: idx_family_member_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_family_member_active ON public.t_family_member USING btree (active_status, owner) WHERE (active_status = true);


--
-- Name: idx_family_member_insurance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_family_member_insurance ON public.t_family_member USING btree (insurance_member_id) WHERE (insurance_member_id IS NOT NULL);


--
-- Name: idx_family_member_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_family_member_owner ON public.t_family_member USING btree (owner);


--
-- Name: idx_family_member_relationship; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_family_member_relationship ON public.t_family_member USING btree (owner, relationship);


--
-- Name: idx_medical_expense_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_active ON public.t_medical_expense USING btree (active_status, service_date);


--
-- Name: idx_medical_expense_claim_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_claim_number ON public.t_medical_expense USING btree (claim_number) WHERE (claim_number IS NOT NULL);


--
-- Name: idx_medical_expense_claim_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_claim_status ON public.t_medical_expense USING btree (claim_status);


--
-- Name: idx_medical_expense_family_member; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_family_member ON public.t_medical_expense USING btree (family_member_id);


--
-- Name: idx_medical_expense_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_owner ON public.t_medical_expense USING btree (owner);


--
-- Name: idx_medical_expense_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_provider ON public.t_medical_expense USING btree (provider_id);


--
-- Name: idx_medical_expense_service_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_expense_service_date ON public.t_medical_expense USING btree (service_date);


--
-- Name: idx_medical_expense_transaction; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_medical_expense_transaction ON public.t_medical_expense USING btree (transaction_id);


--
-- Name: idx_medical_provider_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_active ON public.t_medical_provider USING btree (active_status, provider_name) WHERE (active_status = true);


--
-- Name: idx_medical_provider_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_location ON public.t_medical_provider USING btree (state, city) WHERE ((state IS NOT NULL) AND (city IS NOT NULL));


--
-- Name: idx_medical_provider_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_name ON public.t_medical_provider USING btree (provider_name);


--
-- Name: idx_medical_provider_network; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_network ON public.t_medical_provider USING btree (network_status, provider_type);


--
-- Name: idx_medical_provider_npi; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_npi ON public.t_medical_provider USING btree (npi) WHERE (npi IS NOT NULL);


--
-- Name: idx_medical_provider_specialty; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_specialty ON public.t_medical_provider USING btree (specialty) WHERE (specialty IS NOT NULL);


--
-- Name: idx_medical_provider_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_provider_type ON public.t_medical_provider USING btree (provider_type);


--
-- Name: idx_parameter_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_parameter_owner ON public.t_parameter USING btree (owner);


--
-- Name: idx_payment_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_owner ON public.t_payment USING btree (owner);


--
-- Name: idx_receipt_image_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_receipt_image_owner ON public.t_receipt_image USING btree (owner);


--
-- Name: idx_reward_owner_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reward_owner_account ON public.t_reward USING btree (owner, account_id);


--
-- Name: idx_token_blacklist_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_token_blacklist_expires_at ON public.t_token_blacklist USING btree (expires_at);


--
-- Name: idx_transaction_account_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_account_lookup ON public.t_transaction USING btree (account_name_owner, active_status, transaction_date DESC);


--
-- Name: idx_transaction_account_name_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_account_name_owner ON public.t_transaction USING btree (account_name_owner);


--
-- Name: idx_transaction_active_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_active_status ON public.t_transaction USING btree (active_status) WHERE (active_status = true);


--
-- Name: idx_transaction_categories_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_categories_owner ON public.t_transaction_categories USING btree (owner);


--
-- Name: idx_transaction_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_date ON public.t_transaction USING btree (transaction_date);


--
-- Name: idx_transaction_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_owner ON public.t_transaction USING btree (owner);


--
-- Name: idx_transaction_transaction_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transaction_transaction_state ON public.t_transaction USING btree (transaction_state);


--
-- Name: idx_transfer_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transfer_owner ON public.t_transfer USING btree (owner);


--
-- Name: idx_validation_amount_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_validation_amount_owner ON public.t_validation_amount USING btree (owner);


--
-- Name: t_transaction_categories tr_insert_transaction_categories; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_insert_transaction_categories BEFORE INSERT ON public.t_transaction_categories FOR EACH ROW EXECUTE FUNCTION public.fn_insert_transaction_categories();


--
-- Name: t_transaction_categories tr_update_transaction_categories; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tr_update_transaction_categories BEFORE UPDATE ON public.t_transaction_categories FOR EACH ROW EXECUTE FUNCTION public.fn_update_transaction_categories();


--
-- Name: t_validation_amount fk_account_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_validation_amount
    ADD CONSTRAINT fk_account_id FOREIGN KEY (owner, account_id) REFERENCES public.t_account(owner, account_id) ON UPDATE CASCADE;


--
-- Name: t_transaction fk_account_id_account_name_owner; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT fk_account_id_account_name_owner FOREIGN KEY (owner, account_id, account_name_owner, account_type) REFERENCES public.t_account(owner, account_id, account_name_owner, account_type) ON UPDATE CASCADE;


--
-- Name: t_transaction fk_category_name; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT fk_category_name FOREIGN KEY (owner, category) REFERENCES public.t_category(owner, category_name) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: t_transaction fk_description_name; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT fk_description_name FOREIGN KEY (owner, description) REFERENCES public.t_description(owner, description_name) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: t_transfer fk_destination_account; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT fk_destination_account FOREIGN KEY (owner, destination_account) REFERENCES public.t_account(owner, account_name_owner) ON UPDATE CASCADE;


--
-- Name: t_medical_expense fk_medical_expense_family_member; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense
    ADD CONSTRAINT fk_medical_expense_family_member FOREIGN KEY (owner, family_member_id) REFERENCES public.t_family_member(owner, family_member_id) ON UPDATE CASCADE;


--
-- Name: t_medical_expense fk_medical_expense_provider; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense
    ADD CONSTRAINT fk_medical_expense_provider FOREIGN KEY (provider_id) REFERENCES public.t_medical_provider(provider_id);


--
-- Name: t_medical_expense fk_medical_expense_transaction; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_medical_expense
    ADD CONSTRAINT fk_medical_expense_transaction FOREIGN KEY (owner, transaction_id) REFERENCES public.t_transaction(owner, transaction_id) ON DELETE CASCADE;


--
-- Name: t_payment fk_payment_destination_account; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT fk_payment_destination_account FOREIGN KEY (owner, destination_account) REFERENCES public.t_account(owner, account_name_owner) ON UPDATE CASCADE;


--
-- Name: t_payment fk_payment_guid_destination; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT fk_payment_guid_destination FOREIGN KEY (guid_destination) REFERENCES public.t_transaction(guid) ON UPDATE CASCADE;


--
-- Name: t_payment fk_payment_guid_source; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT fk_payment_guid_source FOREIGN KEY (guid_source) REFERENCES public.t_transaction(guid) ON UPDATE CASCADE;


--
-- Name: t_payment fk_payment_source_account; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT fk_payment_source_account FOREIGN KEY (owner, source_account) REFERENCES public.t_account(owner, account_name_owner) ON UPDATE CASCADE;


--
-- Name: t_transaction fk_receipt_image; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transaction
    ADD CONSTRAINT fk_receipt_image FOREIGN KEY (receipt_image_id) REFERENCES public.t_receipt_image(receipt_image_id) ON UPDATE CASCADE;


--
-- Name: t_transfer fk_source_account; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT fk_source_account FOREIGN KEY (owner, source_account) REFERENCES public.t_account(owner, account_name_owner) ON UPDATE CASCADE;


--
-- Name: t_receipt_image fk_transaction; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_receipt_image
    ADD CONSTRAINT fk_transaction FOREIGN KEY (owner, transaction_id) REFERENCES public.t_transaction(owner, transaction_id) ON UPDATE CASCADE;


--
-- Name: t_transfer fk_transfer_guid_destination; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT fk_transfer_guid_destination FOREIGN KEY (guid_destination) REFERENCES public.t_transaction(guid) ON UPDATE CASCADE;


--
-- Name: t_transfer fk_transfer_guid_source; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_transfer
    ADD CONSTRAINT fk_transfer_guid_source FOREIGN KEY (guid_source) REFERENCES public.t_transaction(guid) ON UPDATE CASCADE;


--
-- Name: t_reward t_reward_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_reward
    ADD CONSTRAINT t_reward_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.t_account(account_id);


--
-- PostgreSQL database dump complete
--



-- Seed data (removed again by run-backup.py before it imports real rows).
INSERT INTO public.t_medical_provider (provider_name, provider_type, specialty, network_status) VALUES
('unknown_provider', 'general', NULL, 'unknown'),
('pharmacy_generic', 'pharmacy', 'retail_pharmacy', 'unknown'),
('urgent_care_generic', 'urgent_care', NULL, 'unknown'),
('hospital_generic', 'hospital', NULL, 'unknown'),
('laboratory_generic', 'laboratory', 'general_lab', 'unknown');

-- Default "self" family member for every active account owner.
INSERT INTO public.t_family_member (owner, member_name, relationship)
SELECT DISTINCT account_name_owner, account_name_owner, 'self'
FROM public.t_account
WHERE active_status = true
AND account_name_owner NOT IN (
    SELECT owner FROM public.t_family_member WHERE relationship = 'self'
);

COMMIT;
