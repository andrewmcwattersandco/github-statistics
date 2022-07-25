#!/bin/sh
remaining=1
query='SELECT id FROM repositories ORDER BY id DESC LIMIT 1'
per_page=100
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  # Get last user
  if [ -f github-repositories.db ]
  then
    since=$(sqlite3 github-repositories.db "$query")
  else
    since=0
  fi
  if
    curl \
      -D store.txt \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -S \
      -s \
      "https://api.github.com/repositories?per_page=${per_page}&since=${since}" \
      > repositories.json
    grep -q 'HTTP/2 200' store.txt
  then
    # Insert repositories
    if
      # BUG: sqlite-utils can return "Error: Rows must all be dictionaries, got:
      # None" on valid JSON. This if-clause prints the response from curl for
      # debugging, then halves `per_page` and tries again.
      ! sqlite-utils insert github-repositories.db repositories - --pk=id \
      < repositories.json
    then
      # cat repositories.json
      per_page=$((per_page / 2))
      printf "repositories: failed to insert repositories, retrying with \
per_page=%s\n" $per_page
    else
      per_page=100
    fi
  else
    # The time at which the current rate limit window resets in UTC epoch
    # seconds.
    reset=$(grep 'x-ratelimit-reset' store.txt)
    echo "$reset"
    reset=$(echo "$reset" | tr -cd '[:digit:]')

    # `x-ratelimit-reset` - current time
    remaining=$((reset - $(date -u "+%s")))
    if [ $remaining -gt 0 ]
    then
        echo "$remaining seconds until rate limit reset"
    fi

    # {"message": ".*"} -> message: .*
    grep -Eo '("message":)\s*(".*")' repositories.json | tr -d '"'
    exit
  fi

  # The number of requests remaining in the current rate limit window.
  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
