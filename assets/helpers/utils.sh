export TMPDIR=${TMPDIR:-/tmp}

hash() {
  sha=$(which sha256sum || which shasum)
  echo "$1" | $sha | awk '{ print $1 }'
}

contains_element() {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

hide_password() {
  if ! echo "$1" | jq -c '.' > /dev/null 2> /dev/null; then
    echo "(invalid json: $1)>"
    exit 1
  fi

  local paths=$(echo "${1:-{\} }" | jq -c "paths")
  local query=""
  if [ -n "$paths" ]; then
    while read path; do
      local parts=$(echo "$path" | jq -r '.[]')
      local selection=""
      local found=""
      while read part; do
        selection+=".$part"
        if [ "$part" == "password" ]; then
          found="true"
        fi
      done <<< "$parts"

      if [ -n "$found" ]; then
        query+=" | jq -c '$selection = \"*******\"'"
      fi
    done <<< "$paths"
  fi

  local json="${1//\"/\\\"}"
  eval "echo \"$json\" $query"
}

log() {
  # $1: message
  # $2: json
  local message="$(date -u '+%F %T') - $1"
  if [ -n "$2" ]; then
   message+=" - $(hide_password "$2")"
  fi
  echo "$message" >&2
}

replace () {
  local source="$1"
  local search="$2"
  local replace="$3"

  echo "${source//$search/$replace}"
}

replace_placeholder () {
  local source="$1"
  local placeholder="$2"
  local value="$3"

  replace "$source" "%%$placeholder%%" "$value"
}

tmp_file() {
  echo "$TMPDIR/bitbucket-pipelines-discovery-resource-$1"
}

tmp_file_unique() {
  mktemp "$TMPDIR/bitbucket-pipelines-discovery-resource-$1.XXXXXX"
}

configure_credentials() {
  local username=$(jq -r '.source.username // ""' < $1)
  local password=$(jq -r '.source.password // ""' < $1)

  rm -f $HOME/.netrc
  if [ "$username" != "" -a "$password" != "" ]; then
    echo "default login $username password $password" > $HOME/.netrc
  fi
}

version() {
  # $1: payload of all retrieved bitbucket repositories/branches
  # $2: input payload
  local version=$(jq -c "sort" < "$1")
  local version_hash=$(hash "$version")
  local previous_hash=$(jq -r '.version.hash // ""' < "$2")

  # compare version hash with previous version and only if different expose a new version timestamp
  if [ "$version_hash" != "$previous_hash" ]; then
    jq -n "{ hash: \"$version_hash\", time: \"$(date)\" }"
  else
    jq -n "$(jq -c '.version' < "$2")"
  fi
}
