#!/bin/sh
getfollowers() {
  if [ -n "$2" ]
  then
    URL="https://api.github.com/users/${1}/followers?per_page=100&page=${2}"
  else
    URL="https://api.github.com/users/${1}/followers?per_page=100"
  fi

  curl \
    -D store.txt \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -S \
    -s \
    "$URL" \
    > followers.json
  grep -q 'HTTP/2 200' store.txt
  return $?
}

id=0
remaining=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  # Get user
  query="\
    SELECT id, login, followers_url \
    FROM users \
    WHERE id > ${id} \
    ORDER BY id \
    LIMIT 1"
  result=$(sqlite3 github-users.db "$query")

  # id|login|followers_url
  id=$(echo "$result" | cut -f 1 -d '|')
  username=$(echo "$result" | cut -f 2 -d '|')
  followers_url=$(echo "$result" | cut -f 3 -d '|')

  # 0 rows
  if [ -z "$followers_url" ]
  then
    exit
  fi

  # Get followers
  if
    getfollowers "$username"
  then
    # Insert followers
    # sqlite-utils insert github-users.db users-followers - --pk=id \
    # < followers.json

    # Get `page` parameter
    page=$(
      pcregrep -o1 'link: <.+>; rel="next", <.+&page=(\d+)>; rel="last"' \
      < store.txt
    )
    count=$((100 * (page - 1)))

    # Get number of followers on the last page
    getfollowers "$username" "$page"
    followers=$(jq 'length' followers.json)
    count=$((count + followers))
    echo "$username has $count followers"
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
