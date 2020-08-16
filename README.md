# on macos
createuser postgres

## restart
brew services restart postgres

## foreign key constraint


ALTER TABLE t_account ADD constraint unique_account unique (account_name_owner);
ALTER TABLE t_transaction ADD CONSTRAINT fk_account_id
   FOREIGN KEY(account_id, account_name_owner)
      REFERENCES t_account(account_id, account_name_owner);
