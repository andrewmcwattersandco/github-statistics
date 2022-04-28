#!/bin/sh
ls -la
remaining=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  since=$(sqlite3 github-statistics.db 'SELECT id FROM users ORDER BY id DESC LIMIT 1')
  if curl \
    -D store.txt \
    --fail-with-body \
    -H "Accept: application/vnd.github.v3+json" \
    -H 'Authorization: Bearer ${{ secrets.GITHUB_TOKEN }}' \
    -S \
    -s \
    "https://api.github.com/users?per_page=100&since=${since}" > users.json
  then
    sqlite-utils insert github-statistics.db users - --pk=id < users.json
  else
    reset=$(grep 'x-ratelimit-reset' store.txt)
    echo "$reset"
    reset=$(echo "$reset" | tr -cd '[:digit:]')
    grep 'message' users.json
  fi

  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
