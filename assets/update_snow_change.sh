#!/bin/bash

set -euo pipefail

# set DEBUG to false, will be evaluated in main()
DEBUG=false

# error output function
err() {
  # date format year-month-day hour:minute:second.millisecond+timezone - requires coreutils date
    echo "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Error - $1" >&2
}

dbg() {
  # date format year-month-day hour:minute:second.millisecond+timezone - requires coreutils date
  if [[ "$DEBUG" == true ]]; then
    echo "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Debug - $1" >&2
  fi
}

# check if required apps are installed
check_application_installed() {
    dbg "check_application_installed(): Checking if $1 is installed."

    if [ -x "$(command -v "${1}")" ]; then
      true
    else
      false
    fi
}

token_auth() {
  # parameters username, password, client_id, client_secret, oauth_URL
  # returns bearer token
  # called with: token_auth -O "${oauth_URL}" -u "${username}" -p "${password}" -C "${client_id}" -S "${client_secret}" -o "${timeout}" # optional -g "${grant_type}"
  local OPTIND=1 # reset OPTIND so getopts starts at 1 and parameters are parsed correctly

  local username=""
  local password=""
  local client_id=""
  local client_secret=""
  local oauth_URL=""
  local timeout="60"
  local response=""
  local bearer_token=""
  local grant_type="password" # optional passed parameter, default to password, unlikely to need anything else set

  # parse arguments. use substitution to set grant_type default to 'password'
  while getopts ":u:p:C:S:O:o:g:" arg; do
    case "${arg}" in
      u) username="${OPTARG}" ;;
      p) password="${OPTARG}" ;;
      C) client_id="${OPTARG}" ;;
      S) client_secret="${OPTARG}" ;;
      O) oauth_URL="${OPTARG}" ;;
      o) timeout="${OPTARG}" ;;
      g) grant_type="${OPTARG}" ;;
      *)
        err "Invalid option: -$OPTARG"
        exit 1
        ;;
    esac
  done

  # debug output all passed parameters
  dbg "token_auth(): All passed parameters:"
  dbg " username: $username"
  if [[ "$DEBUG_PASS" == true ]]; then
    dbg " password: $password"
    dbg " client_id: $client_id"
    dbg " client_secret: $client_secret"
  fi
  dbg " oauth_URL: $oauth_URL"
  dbg " timeout: $timeout"
  dbg " grant_type: $grant_type"


  # ensure required parameters are set
  if [[ -z "$username" || -z "$password" || -z "$client_id" || -z "$client_secret" || -z "$oauth_URL" ]]; then
    err "token_auth(): Missing required parameters: username, password, client_id, client_secret, and oauth_URL."
    exit 1
  fi

  # get bearer token
  # save HTTP response code to variable 'code', API response to variable 'body'
  # https://superuser.com/a/1321274
  dbg "token_auth(): Attempting to authenticate with OAuth."
  response=$(curl -s -k --location -w "\n%{http_code}" -X POST -d "grant_type=$grant_type" -d "username=$username" -d "password=$password" -d "client_id=$client_id" -d "client_secret=$client_secret" "$oauth_URL")
  body=$(echo "$response" | sed '$d')
  code=$(echo "$response" | tail -n1)
  # curl -s -w -k  --location "\n%{http_code}" -X POST -d "grant_type=$grant_type" -d "username=$username" -d "password=$password" -d "client_id=$client_id" -d "client_secret=$client_secret" "$oauth_URL" | {
  #   read -r body
  #   read -r code
  # }

  dbg "token_auth(): HTTP code: $code"
  if [[ -z "$DEBUG_PASS" ]]; then
    dbg "token_auth(): Token auth response: $body"
  fi

  # check if response is 2xx
  if [[ "$code" =~ ^2 ]]; then
    # HTTP 2xx returned, successful API call. get bearer token and clean up
    bearer_token=$(echo "$body" | jq -r '.access_token')
    if [[ -z "$DEBUG_PASS" ]]; then
      dbg "token_auth(): Bearer token: $bearer_token"
    fi
    # return bearer token
    echo "$bearer_token"
  else
    err "Token authentication failed. HTTP response code: $code"
    dbg "Token auth response: $body"
    exit 1
  fi

}