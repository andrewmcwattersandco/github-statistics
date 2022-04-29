#!/bin/sh
ls -la
remaining=1
query='SELECT id FROM users ORDER BY id DESC LIMIT 1'
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  since=$(sqlite3 github-statistics.db "$query")
  if curl \
    -D store.txt \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -S \
    -s \
    "https://api.github.com/users?per_page=100&since=${since}" \
    > users.json
    grep -q 'HTTP/2 200' store.txt
  then
    sqlite-utils insert github-statistics.db users - --pk=id \
    < users.json
  else
    reset=$(grep 'x-ratelimit-reset' store.txt)
    echo "$reset"
    reset=$(echo "$reset" | tr -cd '[:digit:]')

    remaining=$((reset - $(date +%s)))
    if [ $remaining -gt 0 ]
    then
        echo "$remaining seconds until rate limit reset"
    fi

    grep -Eo '("message":)\s*(".*")' users.json | tr -d '"'
    exit
  fi

  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
