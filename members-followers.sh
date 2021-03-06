#!/bin/sh
org=$1
if [ -z "$org" ]; then
  printf "usage: %s: org\n" $0
  exit 2
fi

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

# Get last user
query='SELECT id FROM members_followers ORDER BY id DESC LIMIT 1'
if sqlite3 "${org}.db" "$query" > /dev/null 2>&1
then
  id=$(sqlite3 "${org}.db" "$query")
else
  id=0
fi

remaining=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  # Get user
  query="\
    SELECT id, login, followers_url \
    FROM members \
    WHERE id > ${id} \
    ORDER BY id \
    LIMIT 1"
  result=$(sqlite3 "${org}.db" "$query")

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
    # Get `page` parameter
    page=$(
      pcregrep -o1 'link: <.+>; rel="next", <.+&page=(\d+)>; rel="last"' \
      < store.txt
    )
    if [ -z "$page" ]
    then
      page=1
      count=0
    else
      count=$((100 * (page - 1)))
    fi

    # Get number of followers on the last page
    getfollowers "$username" "$page"
    followers=$(jq 'length' followers.json)
    count=$((count + followers))
    echo "$username has $count followers"

    # Insert followers
    echo "{\
  \"id\": ${id},\
  \"count\": ${count}\
}" | \
    sqlite-utils insert "${org}.db" members_followers - --pk=id
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

    # { "message": ".*" } -> message: .*
    grep -Eo '("message":)\s*(".*")' followers.json | tr -d '"'
    exit
  fi

  # The number of requests remaining in the current rate limit window.
  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
