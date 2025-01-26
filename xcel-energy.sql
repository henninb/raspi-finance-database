-- Start the transaction
BEGIN;

-- Import the data from the CSV file into the target table
\COPY t_transaction FROM 'xcel-energy.csv' WITH CSV HEADER;

-- Commit the transaction to ensure the changes are saved
COMMIT;
