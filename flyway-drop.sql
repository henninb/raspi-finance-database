-- psql -t -h 192.168.100.124 -p 5432 -U henninb -F t -d finance_test_db < "flyway-drop.sql"
drop table flyway_schema_history;
