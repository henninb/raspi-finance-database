#!/bin/sh

# find backups older than 90 days
find . -type f -maxdepth 1 -mtime +90 -name "finance_db*.tar" -print0

exit 1
find . -type f -maxdepth 1 -mtime +90 -name "finance_db*.tar" -print0 | xargs -0 rm

exit 0
