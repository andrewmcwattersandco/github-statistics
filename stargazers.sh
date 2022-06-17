#!/bin/sh
getstargazers() {
  if [ -n "$2" ]
  then
    URL="https://api.github.com/repos/${1}/stargazers?per_page=100&page=${2}"
  else
    URL="https://api.github.com/repos/${1}/stargazers?per_page=100"
  fi

  curl \
    -D store.txt \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -S \
    -s \
    "$URL" \
    > stargazers.json
  grep -q 'HTTP/2 200' store.txt
  return $?
}

# Get last repository
query='SELECT id FROM repositories_stargazers ORDER BY id DESC LIMIT 1'
if sqlite3 github-repositories.db "$query" > /dev/null 2>&1
then
  id=$(sqlite3 github-repositories.db "$query")
else
  id=0
fi

remaining=1
while [ -n "$remaining" ] && [ $remaining -gt 0 ]
do
  # Get repository
  query="\
    SELECT id, full_name, stargazers_url \
    FROM repositories \
    WHERE id > ${id} \
    ORDER BY id \
    LIMIT 1"
  result=$(sqlite3 github-repositories.db "$query")

  # id|full_name|stargazers_url
  id=$(echo "$result" | cut -f 1 -d '|')
  full_name=$(echo "$result" | cut -f 2 -d '|')
  stargazers_url=$(echo "$result" | cut -f 3 -d '|')

  # 0 rows
  if [ -z "$stargazers_url" ]
  then
    exit
  fi

  # Get stargazers
  if
    getstargazers "$full_name"
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

    # Get number of stargazers on the last page
    getstargazers "$full_name" "$page"
    stargazers=$(jq 'length' stargazers.json)
    count=$((count + stargazers))
    echo "$full_name has $count stargazers"

    # Insert stargazers
    echo "{\
  \"id\": ${id},\
  \"count\": ${count},\
  \"created_at\": $(date -u "+%s"),\
  \"updated_at\": null\
}" | \
    sqlite-utils insert github-repositories.db repositories_stargazers - --pk=id
  else
    # Status-code
    status_code=$(head -n 1 store.txt | awk '{ print $2 }')
    if [ "$status_code" = '401' ]
    then
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
      grep -Eo '("message":)\s*(".*")' stargazers.json | tr -d '"'
      exit
    elif [ "$status_code" = '404' ]
    then
      echo "$full_name not found"

      # { "message": ".*" } -> message: .*
      grep -Eo '("message":)\s*(".*")' stargazers.json | tr -d '"'
      continue
    fi
  fi

  # The number of requests remaining in the current rate limit window.
  remaining=$(grep 'x-ratelimit-remaining' store.txt)
  echo "$remaining"
  remaining=$(echo "$remaining" | tr -cd '[:digit:]')
done
