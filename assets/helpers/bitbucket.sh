#!/bin/bash

ASSETS=$(cd "$(dirname "$0")" && pwd)
source $ASSETS/helpers/utils.sh

VALUES_LIMIT=100

bitbucket_request() {
  # $1: host
  # $2: path
  # $3: query
  # $4: netrc file (default: $HOME/.netrc)
  # $5: recursive data for bitbucket paging

  local netrc_file=${4:-$HOME/.netrc}
  local recursive=${5:-"limit=${VALUES_LIMIT}"}

  local request_url="${1}/rest/api/1.0/${2}?${recursive}&${3}"
  local request_result=$(tmp_file_unique bitbucket-request)

  if ! curl -s --netrc-file "$netrc_file" -o "$request_result" "$request_url"; then
    log "Bitbucket request $request_url failed"
    exit 1
  fi

  if ! jq -c '.' < "$request_result" > /dev/null 2> /dev/null; then
    log "Bitbucket request $request_url failed: invalid JSON"
    exit 1
  fi

  if [ "$(jq -r '.isLastPage' < "$request_result")" == "false" ]; then
    local nextPage=$(jq -r '.nextPageStart' < "$request_result")
    local nextResult=$(bitbucket_request "$1" "$2" "$3" "$4" "start=${nextPage}&limit=${VALUES_LIMIT}")
    jq -c '.values' < "$request_result" | jq -c ". + $nextResult"
  elif [ "$(jq -c '.values' < "$request_result")" != "null" ]; then
    jq -c '.values' < "$request_result"
  else
    log "Bitbucket request ($request_url) failed: $(cat $request_result)"
    exit 1
  fi

  # cleanup
  rm -f "$request_result"
}

bitbucket_repos() {
  # $1: host
  # $2: project
  # $3: cache folder to cache query responses
  # $4: netrc file (default: $HOME/.netrc)
  log "Retrieving repositories for $2"
  set -o pipefail; bitbucket_request "$1" "projects/$2/repos" "" "$3" "$4" | \
    jq '. | map({slug: .slug, name: .name, url: (.links.clone[] | select(.name == "http")) | .href })'
}

bitbucket_branches() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: cache folder to cache query responses
  # $5: netrc file (default: $HOME/.netrc)
  log "Retrieving branches for $3 in $2"
  set -o pipefail; bitbucket_request "$1" "projects/$2/repos/$3/branches" "" "$4" "$5" | \
    jq '. | map({ name: .displayId, default: .isDefault })'
}

bitbucket_filter_repos_branches() {
  # $1: JSON payload file
  # $2: handle function for a bitbucket scanned source
  # $@: other parameters that will be passed to $2

  local payload="$1"
  local handle_source="$2"
  shift
  shift

  # create tmp files
  repositories_payload=$(tmp_file_unique bitbucket-repos)
  branches_payload=$(tmp_file_unique bitbucket-branches)

  # deletes the temp files
  function bitbucket_cleanup {
    rm -f "$repositories_payload"
    rm -f "$branches_payload"
    log "Deleted temp bitbucket result files"
  }

  # register the cleanup function to be called on the EXIT signal
  trap bitbucket_cleanup EXIT

  log "Scanning bitbucket server for repositories to discover..."
  host=$(jq -r '.source.host // ""' < "$payload")
  project=$(jq -r '.source.project // ""' < "$payload")
  repository_pattern=$(jq -r '.source.repository // ""' < "$payload")
  branch_pattern=$(jq -r '.source.branch // ""' < "$payload")

  # setup credentials, if none are specified use those from source
  configure_credentials "$payload"

  # get all repositories matching pattern
  set -o pipefail; bitbucket_repos "$host" "$project" | jq -c ".[]" > "$repositories_payload"

  while read repository; do
    repo_name=$(echo "$repository" | jq -r '.name')
    if echo "$repo_name" | grep -Ec "$repository_pattern" > /dev/null; then

      repo_slug=$(echo "$repository" | jq -r '.slug')
      repo_url=$(echo "$repository" | jq -r '.url')

      # if no branch pattern is provided only the default branch is selected
      branch_selector=""
      if [ -z "$branch_pattern" ]; then
        branch_selector="| select(.default == true)"
      fi

      # get all branches for specific repository matching pattern
      set -o pipefail; bitbucket_branches "$host" "$project" "$repo_slug" | jq -c ".[] $branch_selector" > "$branches_payload"

      # add source for repository/branch
      branches=$(jq -c "{ name: \"${repo_slug}\", uri: \"${repo_url}\", branch: .name }" < "$branches_payload")
      if [ -n "$branches" ]; then
        while read branch ; do
          branch_name=$(echo "$branch" | jq -r '.branch')
          if echo "$branch_name" | grep -Ec "$branch_pattern" > /dev/null; then
            $handle_source "$@" <<< "$branch"
          fi
        done <<< "$branches"
      fi
    fi
  done < "$repositories_payload"
}
