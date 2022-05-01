#!/bin/sh
org=$1
if [ -z "$org" ]; then
  printf "usage: %s: org\n" $0
  exit 2
fi

getmembers() {
  if [ -n "$2" ]
  then
    URL="https://api.github.com/orgs/${1}/members?per_page=100&page=${2}"
  else
    URL="https://api.github.com/orgs/${1}/members?per_page=100"
  fi

  curl \
    -D store.txt \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -S \
    -s \
    "$URL" \
    > members.json
  grep -q 'HTTP/2 200' store.txt
  return $?
}

remaining=1
page=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  if
    getmembers "$org" "$page"
  then
    # Insert members
    sqlite-utils insert "${org}.db" members - --pk=id < members.json
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

    # {"message": ".*"} -> message: .*
    grep -Eo '("message":)\s*(".*")' members.json | tr -d '"'
    exit
  fi

  # The number of requests remaining in the current rate limit window.
  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')

  # Get next page
  page=$(pcregrep -o1 'link: <.+&page=(\d+)>; rel="next"' store.txt)
  if [ -z "$page" ]
  then
    exit
  fi
done
