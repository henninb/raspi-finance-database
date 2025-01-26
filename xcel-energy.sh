#!/bin/sh

#psql -h finance-db -U henninb -d finance_db -c "\COPY t_transaction FROM 'xcel-energy.csv' WITH CSV HEADER"
psql -h finance-db -U henninb -d finance_db -f xcel-energy.sql

exit 0
