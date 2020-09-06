with new_a as (
  update t_transaction set account_name_owner ='chase-amazon_brian' where account_name_owner ='amazon_brian'
)
update t_account set account_name_owner ='chase-amazon_brian' where account_name_owner ='amazon_brian';
