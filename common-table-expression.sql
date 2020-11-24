with change_account_name as (
  update t_transaction set account_name_owner ='chase-amazon_brian' where account_name_owner ='amazon_brian'
)
update t_account set account_name_owner ='chase-amazon_brian' where account_name_owner ='amazon_brian';



with delete_images as (
  update t_transaction set receipt_image_id=null where receipt_image_id in (select receipt_image_id from t_receipt_image where length(jpg_image)=8563)
)
delete from t_receipt_image where receipt_image_id in(select receipt_image_id from t_receipt_image where length(jpg_image)=8563);
