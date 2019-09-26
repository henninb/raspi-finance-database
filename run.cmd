@echo off

rem C:\Program Files (x86)\pgAdmin 4\v2\runtime

type aaaa_tables.sql aaab_tables.sql example.sql zzzy_tables.sql zzzz_tables.sql > master.sql

psql -h 192.168.100.25 -p 5432 -d postgres -U henninb < master.sql > log.txt 2>&1

pause
