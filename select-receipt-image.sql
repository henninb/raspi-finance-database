--select encode(receipt_image::bytea, 'hex') from t_transaction where guid='6c7fda78-5f87-4a67-8870-29b2fbf9ebee'
select receipt_image from t_transaction where guid='6c7fda78-5f87-4a67-8870-29b2fbf9ebee'
