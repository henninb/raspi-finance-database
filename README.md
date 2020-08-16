# on macos
createuser postgres

## restart
brew services restart postgres

## foreign key constraint
CONSTRAINT fk_account_id
   FOREIGN KEY(account_id, account_name_owner)
      REFERENCES t_account(account_id, account_name_owner)
