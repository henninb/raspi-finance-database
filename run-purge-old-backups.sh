#!/bin/sh

# find backups older than 90 days
find . -maxdepth 1 -type f -mtime +90 -name "finance_db*.tar"

find . -maxdepth 1 -type f -mtime +90 -name "finance_db*.tar" -print0 | xargs -0 rm

exit 0
