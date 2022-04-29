#!/bin/sh
id=0
remaining=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  # Get user
  query="\
    SELECT id, followers_url \
    FROM users \
    WHERE id > ${id} \
    ORDER BY id \
    LIMIT 1"
  result=$(sqlite3 github-users.db "$query")

  # id|followers_url
  id=$(echo "$result" | cut -f 1 -d '|')
  followers_url=$(echo "$result" | cut -f 2 -d '|')

  # 0 rows
  if [ -z "$followers_url" ]
  then
    exit
  fi

  # Get followers
  if
    curl \
      -D store.txt \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -S \
      -s \
      "$followers_url?per_page=100" \
      > followers.json
    grep -q 'HTTP/2 200' store.txt
  then
    # Insert followers
    # sqlite-utils insert github-users.db users-followers - --pk=id \
    # < followers.json

    # Get `page` parameter
    page=$(
      pcregrep -o1 'link: <.+>; rel="next", <.+&page=(\d+)>; rel="last"' \
      < store.txt
    )
    pages=$((page - 1))
    count=$((100 * pages))

    # TODO: Get number of followers on the last page
    followers=0
    count=$((count + followers))
  else
    # The time at which the current rate limit window resets in UTC epoch
    # seconds.
    reset=$(grep 'x-ratelimit-reset' store.txt)
    echo "$reset"
    reset=$(echo "$reset" | tr -cd '[:digit:]')

    # `x-ratelimit-reset` - current time
    remaining=$((reset - $(date +%s)))
    if [ $remaining -gt 0 ]
    then
        echo "$remaining seconds until rate limit reset"
    fi

    # { "message": ".*" } -> message: .*
    grep -Eo '("message":)\s*(".*")' users.json | tr -d '"'
    exit
  fi

  # The number of requests remaining in the current rate limit window.
  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
