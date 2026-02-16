#!/bin/sh

pg_dump --schema-only "host=192.168.10.10 dbname=finance_db user=henninb sslmode=require" > schema.sql

exit 0
