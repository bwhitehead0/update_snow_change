#!/bin/bash

set -euo pipefail

# set DEBUG to false, will be evaluated in main()
DEBUG="false"

# error output function
err() {
  # date format year-month-day hour:minute:second.millisecond+timezone - requires coreutils date
    printf '%s\n' "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Error - $1" >&2
}

dbg() {
  # date format year-month-day hour:minute:second.millisecond+timezone - requires coreutils date
  if [[ "$DEBUG" == "true" ]]; then
    printf '%s\n' "$(date +'%Y-%m-%dT%H:%M:%S.%3N%z') - Debug - $1" >&2
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

escape_json() {
  # updated perl to handle newlines and carriage returns without double escaping
  local input="$1"
  local escaped=""
  # escaped=$(printf '%s' "$input" | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\//\\\//g; s/\x08/\\b/g; s/\f/\\f/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g')
  escaped=$(printf '%s' "$input" | perl -pe 's/\\(?![nrtbf\/"])/\\\\/g; s/"/\\"/g; s/\//\\\//g; s/\x08/\\b/g; s/\f/\\f/g; s/(?<!\\)\n/\\n/g; s/(?<!\\)\r\n/\\r\\n/g; s/\t/\\t/g')
  printf '%s' "$escaped"
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

create_payload_data() {
  # this function creates the JSON payload that's sent to the ServiceNow API to update the change ticket
  # nested function to handle logic and add commas between key/value pairs
  json_with_comma() {
    # ? there might be a more elegant way to handle this both here and in the function calls below
    count=$1
    if [[ "$count" -gt 0 ]]; then
      echo ","
    fi
  }

  # debug output all passed parameters
  dbg "create_payload_data(): All passed parameters: $*"

  # initialize variables
    local OPTIND=1 # reset OPTIND so getopts starts at 1 and parameters are parsed correctly
    local work_notes=""
    local state=""
    local close_code=""
    local close_notes=""
    local payload_data=""
    local kv_pair=0 # counter for key/value pairs

  # parse arguments
  while getopts ":w:s:d:n:" arg; do
    case "${arg}" in
      w) work_notes="${OPTARG}" ;;
      s) state="${OPTARG}" ;;
      d) close_code="${OPTARG}" ;;
      n) close_notes="${OPTARG}" ;;
      :) err "Option -$OPTARG requires an argument."; exit 1 ;;
      ?) err "Invalid option: -$OPTARG"; exit 1 ;;
      *) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done

  # debug output all passed parameters
    dbg "create_payload_data(): All passed parameters:"
    dbg " work_notes: $work_notes"
    dbg " state: $state"
    dbg " close_code: $close_code"
    dbg " close_notes: $close_notes"
    dbg " DEBUG: $DEBUG"
    dbg " DEBUG_PASS: $DEBUG_PASS"
  
  # ensure at least one parameter passed
  if [[ -z "$work_notes" && -z "$state" && -z "$close_code" && -z "$close_notes" ]]; then
    err "create_payload_data(): No parameters passed."
    exit 1
  fi

  # phase 1 for testing we'll just build the k/v pairs and not worry about line breaks or multiline string behavior for work_notes and close_notes. may have to revisit, add escaping, etc.
  # we have to escape work_notes and close_notes now, not later.
  if [[ -n "$work_notes" ]]; then
    dbg "create_payload_data(): Escaping work_notes."
    work_notes=$(escape_json "$work_notes")
    dbg "create_payload_data(): Escaped work_notes: $work_notes"
  fi

  if [[ -n "$close_notes" ]]; then
    dbg "create_payload_data(): Escaping close_notes."
    close_notes=$(escape_json "$close_notes")
    dbg "create_payload_data(): Escaped close_notes: $close_notes"
  fi

  # build key/value pairs for JSON payload
  # check each param, add k/v quoted pair, increment counter, include comma if not first pair
  if [[ -n "$work_notes" ]]; then
    # if work_notes is set, add it to the payload
    # if work_notes is not a JSON object, add it to the payload as a string
    payload_data+="\"work_notes\":\"$work_notes\""
    ((kv_pair++)) # increment counter
  fi
  if [[ -n "$state" ]]; then
    # if state is set, add it to the payload
    payload_data+="$(json_with_comma $kv_pair)\"state\":\"$state\""
    ((kv_pair++)) # increment counter
  fi
  if [[ -n "$close_code" ]]; then
    # if close_code is set, add it to the payload
    payload_data+="$(json_with_comma $kv_pair)\"close_code\":\"$close_code\""
    ((kv_pair++)) # increment counter
  fi
  if [[ -n "$close_notes" ]]; then
    # if close_notes is set, add it to the payload
    payload_data+="$(json_with_comma $kv_pair)\"close_notes\":\"$close_notes\""
    ((kv_pair++)) # increment counter
  fi

  payload_data="{${payload_data}}"
  # silently validate the JSON
  if ! echo "$payload_data" | jq empty > /dev/null 2>&1; then
    err "Invalid JSON payload. Check input values."
    exit 1
  else
    # return json payload
    dbg "create_payload_data(): JSON payload valid."
    echo "${payload_data}"
  fi
  dbg "create_payload_data(): Payload data: $payload_data"

}

update_change_ticket() {
  # API endpoint: https://sn_url.service-now.com/api/sn_chg_rest/v1/change/$change_sys_id
  # parameters: change_sys_id, payload_data, sn_url, bearer_token, timeout
  # called with: update_change_ticket -c "${change_ticket_sys_id}" -p "${payload_data}" -l "${sn_url}" -B "${BEARER_TOKEN}" -t "${timeout}"
  # initialize variables
    local OPTIND=1 # reset OPTIND so getopts starts at 1 and parameters are parsed correctly
    local change_ticket_sys_id=""
    local payload_data=""
    local sn_url=""
    local bearer_token=""
    local timeout="60"
    local api_endpoint="api/sn_chg_rest/v1/change"

  # parse arguments
  while getopts ":c:p:l:B:t:" arg; do
    case "${arg}" in
      c) change_ticket_sys_id="${OPTARG}" ;;
      p) payload_data="${OPTARG}" ;;
      l) sn_url="${OPTARG}" ;;
      B) BEARER_TOKEN="${OPTARG}" ;;
      t) timeout="${OPTARG}" ;;
      :) err "Option -$OPTARG requires an argument."; exit 1 ;;
      ?) err "Invalid option: -$OPTARG"; exit 1 ;;
      *) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done

  # debug output all passed parameters
    dbg "update_change_ticket(): All passed parameters:"
    dbg " change_ticket_sys_id: $change_ticket_sys_id"
    dbg " payload_data: $payload_data"
    dbg " sn_url: $sn_url"
    if [[ "$DEBUG_PASS" == true ]]; then
      dbg " BEARER_TOKEN: $BEARER_TOKEN"
    fi
    dbg " timeout: $timeout"
  
  # ensure required parameters are set
  if [[ -z "$change_ticket_sys_id" || -z "$payload_data" || -z "$sn_url" || -z "$BEARER_TOKEN" ]]; then
    err "update_change_ticket(): Missing required parameters: change_ticket_sys_id, payload_data, sn_url, or BEARER_TOKEN."
    exit 1
  fi

  # build API URL
  api_URL="${sn_url}/${api_endpoint}/${change_ticket_sys_id}"
  dbg "update_change_ticket(): API URL: ${api_URL}"

  # update change ticket

  # save HTTP response code to variable 'code', API response to variable 'body'
  # https://superuser.com/a/1321274
  response=$(curl -s -k --location -w "\n%{http_code}" -X PATCH -H "Authorization: Bearer ${BEARER_TOKEN}" -H "Content-Type: application/json" -d "${payload_data}" "${api_URL}")
  body=$(printf '%s\n' "$response" | sed '$d')
  code=$(echo "$response" | tail -n1)

  dbg "update_change_ticket(): HTTP code: $code"
  # dbg "update_change_ticket(): Response: $body"

  # check if response is 2xx
  if [[ "$code" =~ ^2 ]]; then
    # HTTP 2xx returned, successful API call
    dbg "update_change_ticket(): Change ticket updated successfully."
    printf '%s\n' "$body"
    dbg "update_change_ticket(): Response: $body"
  else
    err "update_change_ticket(): Failed to update change ticket. HTTP response code: $code"
    dbg "update_change_ticket(): Response: $body"
    exit 1
  fi

}

main() {
  # possible parameters: -D DEBUG -P DEBUG_PASS -u username -p password -C client_id -S client_secret -l sn_url -t timeout -w work_notes -U sn_user_id -s state -d close_code -n close_notes -c change_ticket_sys_id -B BEARER_TOKEN
    # -D DEBUG
    # -P DEBUG_PASS
    # -u username
    # -p password
    # -C client_id
    # -S client_secret
    # -l sn_url
    # -t timeout
    # -w work_notes
    # -U sn_user_id
    # -s state
    # -d close_code
    # -n close_notes
    # -c change_ticket_sys_id
    # -B BEARER_TOKEN
  # if bearer token is provided, username, password, client_id, client_secret are ignored, process data for ticket update, and call update function with token, otherwise, authenticate and get token, then process data for ticket update, and call update function with token
  # TODO: double check if we need the sn_user_id, i don't think we can change the user for any actions taken by the service acct
  # ! TODO: add state code input, use 'state' as string value. we should be able to specify state by string value and determine the state code from that. goal is ease of use for users.
  # TODO: future version should probably get ticket data first and dbg log field updates (original value, updated value) where appropriate (ie state change)

  dbg "main(): All passed parameters (\$*): $*"

  # initialize variables
    local sn_url=""
    local username=""
    local password=""
    local timeout="60" # default timeout value
    local oauth_endpoint="oauth_token.do"
    local client_id=""
    local client_secret=""
    local BEARER_TOKEN=""
    local work_notes=""
    local state=""
    local close_code=""
    local close_notes=""
    local change_ticket_sys_id=""
    # DEBUG="false"
    DEBUG_PASS=false

  # parse arguments
  while getopts ":u:p:C:S:l:t:w:s:d:n:c:D:P" arg; do
    case "${arg}" in
      D) DEBUG="${OPTARG}" ;;
      P) DEBUG_PASS=true ;;
      u) username="${OPTARG}" ;;
      p) password="${OPTARG}" ;;
      C) client_id="${OPTARG}" ;;
      S) client_secret="${OPTARG}" ;;
      l) sn_url="${OPTARG}" ;;
      t) timeout="${OPTARG}" ;;
      w) work_notes="${OPTARG}"; dbg "getopts: ${OPTARG}" ;;
      s) state="${OPTARG}" ;;
      d) close_code="${OPTARG}" ;;
      n) close_notes="${OPTARG}" ;;
      c) change_ticket_sys_id="${OPTARG}" ;;
      # B) BEARER_TOKEN="${OPTARG}" ;;
      :) err "Option -$OPTARG requires an argument."; exit 1 ;;
      ?) err "Invalid option: -$OPTARG"; exit 1 ;;
      *) err "Invalid option: -$OPTARG"; exit 1 ;;
    esac
  done

  # DEBUG="true"


  # set DEBUG and DEBUG_PASS as environment variables
  export DEBUG
  export DEBUG_PASS

  # debug output all passed parameters
    dbg "main(): All passed parameters:"
    dbg " sn_url: $sn_url"
    dbg " username: $username"
    if [[ "$DEBUG_PASS" == true ]]; then
      dbg " password: $password"
      dbg " client_id: $client_id"
      dbg " client_secret: $client_secret"
      # dbg " BEARER_TOKEN: $BEARER_TOKEN"
    fi
    dbg " change_ticket_sys_id: $change_ticket_sys_id"
    dbg " timeout: $timeout"
    dbg " work_notes: $work_notes"
    dbg " state: $state"
    dbg " close_code: $close_code"
    dbg " close_notes: $close_notes"
    dbg " change_ticket_sys_id: $change_ticket_sys_id"
    dbg " DEBUG: $DEBUG"
    dbg " DEBUG_PASS: $DEBUG_PASS"

  # check for required parameters
  if [[ -z "$change_ticket_sys_id" || -z "$sn_url" || ( -z "$username" && -z "$password" ) || ( -z "$username" && -z "$password" && -z "$client_id" && -z "$client_secret" ) ]]; then
    err "main(): Missing required parameters: change_ticket, sn_url, and either Username and Password, or Username + Password + Client ID + Client Secret."
    exit 1
  fi

  # VALIDATION STEPS
    # check if jq, curl, perl are installed
    if ! check_application_installed jq; then
      err "jq not available, aborting."
      exit 1
    else
      dbg "main(): jq version: $(jq --version)"
    fi

    if ! check_application_installed curl; then
      err "curl not available, aborting."
      exit 1
    else
      dbg "main(): curl version: $(curl --version | head -n 1)"
    fi

    if ! check_application_installed perl; then
      err "perl not available, aborting."
      exit 1
    else
      dbg "main(): perl version: $(perl --version | sed -n 2p)"
    fi
    # add code to validate state code if passed
    # valid states:
      # new = -5
      # assess = -4
      # authorize = -3
      # scheduled = -2
      # implement = -1
      # review = 0
      # closed = 3
      # canceled = 4
    if [[ -n "$state" ]]; then
      if [[ "$state" =~ ^(new|-5|assess|-4|authorize|-3|scheduled|-2|implement|-1|review|0|closed|3|canceled|4)$ ]]; then
        dbg "main(): Valid state code: $state"
      else
        err "main(): Invalid state code: $state"
        exit 1
      fi
    fi

    # add validation for close_code if passed
    # valid close codes are:
      # Successful
      # Unsuccessful
      # Successful with Issues
    if [[ -n "$close_code" ]]; then
      # should probably normalize case to lower or upper first for the validation, and update to expected corresponding values before sending via API
      if [[ "$close_code" =~ ^(Successful|Unsuccessful|Successful\ with\ Issues)$ ]]; then
        dbg "main(): Valid close code: $close_code"
      else
        err "main(): Invalid close code: $close_code"
        exit 1
      fi
    fi

  # normalize sn_url. remove trailing slash if present
  sn_url=$(echo "$sn_url" | sed 's/\/$//')

  # test if url is valid and reachable
  if ! curl -Lk -s -w "%{http_code}" "$sn_url" -o /dev/null | grep "200" > /dev/null; then
    err "main(): Invalid or unreachable URL: $sn_url"
    exit 1
  fi

  # if user, pass, client_id, and client_secret are set, build oauth URL and authenticate#
  # TODO: logic to separate out auth based on passed parameters, BEARER_TOKEN, user/pass, or user/pass/client_id/client_secret
  # TODO: leaving out using BEARER_TOKEN, we'll need a separate action that only handles auth and that's a process improvement planned for later.
  if [[ -n "$username" && -n "$password" && -n "$client_id" && -n "$client_secret" ]]; then
    oauth_URL="${sn_url}/${oauth_endpoint}"
    dbg "main(): Using OAuth for authentication: ${oauth_URL}"
    BEARER_TOKEN=$(token_auth -O "${oauth_URL}" -u "${username}" -p "${password}" -C "${client_id}" -S "${client_secret}" -o "${timeout}")
    if [[ "$DEBUG_PASS" == true ]]; then
      dbg "main(): BEARER_TOKEN: $BEARER_TOKEN"
    fi
  fi

  # create payload data
  # pass all data params whether set or not, let the function determine whether to use them or not
  payload_data=$(create_payload_data -w "${work_notes}" -s "${state}" -d "${close_code}" -n "${close_notes}")

  # update change ticket
  # called with: update_change_ticket -c "${change_ticket_sys_id}" -p "${payload_data}" -l "${sn_url}" -B "${BEARER_TOKEN}" -t "${timeout}"
  response=$(update_change_ticket -c "${change_ticket_sys_id}" -p "${payload_data}" -l "${sn_url}" -B "${BEARER_TOKEN}" -t "${timeout}")

  # echo "$response"
  # use printf to output the response without interpreting escape sequences
  printf '%s\n' "$response"

}

main "$@"