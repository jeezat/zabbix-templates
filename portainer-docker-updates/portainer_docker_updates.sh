#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_CONFIG_FILE="/etc/zabbix/portainer-docker-updates.conf"
CONFIG_FILE="${PORTAINER_UPDATES_CONFIG:-$DEFAULT_CONFIG_FILE}"
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: portainer_docker_updates.sh [--help]

Checks configured Docker environments via the read-only Portainer API and writes
one JSON document to stdout. Configuration defaults to:
  /etc/zabbix/portainer-docker-updates.conf

For isolated tests, PORTAINER_UPDATES_CONFIG may point to another trusted config.
No API key is accepted as a command-line argument.
EOF
}

json_failure() {
  local message=$1 code=${2:-2}
  jq -cn --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg message "$message" \
    '{status:"error",checked_at:$now,total_updates:0,total_errors:1,environments:[],error:$message}'
  exit "$code"
}

# Called indirectly by trap.
# shellcheck disable=SC2317
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

if (($# > 0)); then
  if (($# == 1)) && [[ $1 == --help || $1 == -h ]]; then
    usage
    exit 0
  fi
  printf 'Unknown argument. Use --help.\n' >&2
  json_failure "invalid arguments" 2
fi

for command in curl jq mktemp date; do
  command -v "$command" >/dev/null 2>&1 || json_failure "required command is missing: $command" 2
done

[[ -f "$CONFIG_FILE" && -r "$CONFIG_FILE" ]] || json_failure "configuration file is missing or unreadable" 2

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${PORTAINER_URL:=}"
: "${PORTAINER_API_KEY_FILE:=}"
: "${PORTAINER_ENVIRONMENTS:=}"
: "${VERIFY_TLS:=true}"
: "${CA_FILE:=}"
: "${CONNECT_TIMEOUT:=10}"
: "${REQUEST_TIMEOUT:=30}"
: "${INCLUDE_STOPPED:=false}"
: "${CONTAINER_INCLUDE_REGEX:=}"
: "${CONTAINER_EXCLUDE_REGEX:=}"
: "${IMAGE_EXCLUDE_REGEX:=}"

[[ $PORTAINER_URL =~ ^https?://[^[:space:]]+$ ]] || json_failure "PORTAINER_URL must be an HTTP(S) URL" 2
[[ ! $PORTAINER_URL =~ ^https?://[^/[:space:]]+@ ]] || json_failure "PORTAINER_URL must not contain credentials" 2
PORTAINER_URL=${PORTAINER_URL%/}
[[ -n $PORTAINER_ENVIRONMENTS ]] || json_failure "PORTAINER_ENVIRONMENTS is empty" 2
[[ $VERIFY_TLS == true || $VERIFY_TLS == false ]] || json_failure "VERIFY_TLS must be true or false" 2
[[ $INCLUDE_STOPPED == true || $INCLUDE_STOPPED == false ]] || json_failure "INCLUDE_STOPPED must be true or false" 2
[[ $CONNECT_TIMEOUT =~ ^[1-9][0-9]*$ ]] || json_failure "CONNECT_TIMEOUT must be a positive integer" 2
[[ $REQUEST_TIMEOUT =~ ^[1-9][0-9]*$ ]] || json_failure "REQUEST_TIMEOUT must be a positive integer" 2
[[ -z $CA_FILE || -r $CA_FILE ]] || json_failure "CA_FILE is unreadable" 2
[[ -f $PORTAINER_API_KEY_FILE && -r $PORTAINER_API_KEY_FILE ]] || json_failure "API key file is missing or unreadable" 2

IFS= read -r API_KEY < "$PORTAINER_API_KEY_FILE" || true
API_KEY=${API_KEY%$'\r'}
[[ -n $API_KEY ]] || json_failure "API key file is empty" 2

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/portainer-updates.XXXXXX") || json_failure "cannot create temporary directory" 2
chmod 700 "$TMP_DIR"
HEADER_FILE="$TMP_DIR/headers"
printf 'X-API-Key: %s\nAccept: application/json\n' "$API_KEY" > "$HEADER_FILE"
chmod 600 "$HEADER_FILE"
unset API_KEY
ENV_LINES="$TMP_DIR/environments.jsonl"
: > "$ENV_LINES"

CURL_ARGS=(--silent --show-error --connect-timeout "$CONNECT_TIMEOUT" --max-time "$REQUEST_TIMEOUT" --header "@$HEADER_FILE")
if [[ $VERIFY_TLS == false ]]; then
  CURL_ARGS+=(--insecure)
elif [[ -n $CA_FILE ]]; then
  CURL_ARGS+=(--cacert "$CA_FILE")
fi

API_HTTP="000"
API_CURL_RC=0
api_get() {
  local url=$1 output=$2 code_file="$TMP_DIR/http-code"
  : > "$output"
  : > "$code_file"
  if curl "${CURL_ARGS[@]}" --output "$output" --write-out '%{http_code}' "$url" > "$code_file"; then
    API_CURL_RC=0
  else
    API_CURL_RC=$?
  fi
  API_HTTP=$(<"$code_file")
  [[ $API_HTTP =~ ^[0-9]{3}$ ]] || API_HTTP="000"
}

http_error_text() {
  local code=$1
  case $code in
    401|403) printf 'authentication or authorization failed (HTTP %s)' "$code" ;;
    404) printf 'resource not found or not authorized (HTTP 404)' ;;
    429) printf 'rate limit exceeded (HTTP 429)' ;;
    5??) printf 'Portainer server error (HTTP %s)' "$code" ;;
    *) printf 'unexpected HTTP status %s' "$code" ;;
  esac
}

curl_error_text() {
  local code=$1
  case $code in
    6|7) printf 'connection failed' ;;
    28) printf 'request timed out' ;;
    35|51|58|60|77|80|82|83|90|91) printf 'TLS verification or TLS connection failed' ;;
    *) printf 'HTTP transport failed (curl exit %s)' "$code" ;;
  esac
}

regex_match() {
  local value=$1 regex=$2
  [[ -n $regex && $value =~ $regex ]]
}

IFS=',' read -r -a ENVIRONMENT_ENTRIES <<< "$PORTAINER_ENVIRONMENTS"
for entry in "${ENVIRONMENT_ENTRIES[@]}"; do
  environment_id=${entry%%:*}
  environment_name=${entry#*:}
  if [[ $entry != *:* || ! $environment_id =~ ^[0-9]+$ || -z $environment_name ]]; then
    printf 'Invalid environment entry ignored: expected numeric-id:name.\n' >&2
    jq -cn --arg id "$environment_id" --arg name "$environment_name" \
      '{id:$id,name:$name,status:"error",updates:0,errors:1,containers:[],error:"invalid environment configuration"}' >> "$ENV_LINES"
    continue
  fi

  list_body="$TMP_DIR/list-${environment_id}.json"
  all=false
  [[ $INCLUDE_STOPPED == true ]] && all=true
  api_get "$PORTAINER_URL/api/endpoints/$environment_id/docker/containers/json?all=$all" "$list_body"
  if ((API_CURL_RC != 0)); then
    error_text=$(curl_error_text "$API_CURL_RC")
    printf 'Environment %s: %s.\n' "$environment_name" "$error_text" >&2
    jq -cn --arg id "$environment_id" --arg name "$environment_name" --arg error "$error_text" \
      '{id:$id,name:$name,status:"error",updates:0,errors:1,containers:[],error:$error}' >> "$ENV_LINES"
    continue
  fi
  if [[ $API_HTTP != 200 ]]; then
    error_text=$(http_error_text "$API_HTTP")
    printf 'Environment %s: %s.\n' "$environment_name" "$error_text" >&2
    jq -cn --arg id "$environment_id" --arg name "$environment_name" --arg error "$error_text" \
      '{id:$id,name:$name,status:"error",updates:0,errors:1,containers:[],error:$error}' >> "$ENV_LINES"
    continue
  fi
  if ! jq -e 'type == "array"' "$list_body" >/dev/null 2>&1; then
    printf 'Environment %s: invalid container-list JSON.\n' "$environment_name" >&2
    jq -cn --arg id "$environment_id" --arg name "$environment_name" \
      '{id:$id,name:$name,status:"error",updates:0,errors:1,containers:[],error:"invalid container-list JSON"}' >> "$ENV_LINES"
    continue
  fi

  container_lines="$TMP_DIR/containers-${environment_id}.jsonl"
  : > "$container_lines"
  eligible_containers=0
  image_status_404_count=0
  image_status_404_reported=false
  while IFS= read -r container; do
    container_id=$(jq -r '.Id // empty' <<< "$container")
    container_name=$(jq -r '(.Names[0] // "") | ltrimstr("/")' <<< "$container")
    image=$(jq -r '.Image // ""' <<< "$container")
    if [[ -z $container_id ]]; then
      continue
    fi

    excluded=false
    if [[ -n $CONTAINER_INCLUDE_REGEX ]] && ! regex_match "$container_name" "$CONTAINER_INCLUDE_REGEX"; then
      excluded=true
    fi
    regex_match "$container_name" "$CONTAINER_EXCLUDE_REGEX" && excluded=true
    regex_match "$image" "$IMAGE_EXCLUDE_REGEX" && excluded=true
    if [[ $excluded == true ]]; then
      jq -cn --arg id "$container_id" --arg name "$container_name" --arg image "$image" \
        '{id:$id,name:$name,image:$image,status:"excluded",update_available:false,error:null}' >> "$container_lines"
      continue
    fi

    eligible_containers=$((eligible_containers + 1))
    status_body="$TMP_DIR/status-${environment_id}-${container_id}.json"
    api_get "$PORTAINER_URL/api/docker/$environment_id/containers/$container_id/image_status" "$status_body"
    image_status_was_404=false
    if ((API_CURL_RC != 0)); then
      error_text=$(curl_error_text "$API_CURL_RC")
      status=error
    elif [[ $API_HTTP != 200 ]]; then
      if [[ $API_HTTP == 404 ]]; then
        error_text="image-status endpoint unavailable or container not found (HTTP 404); Portainer CE does not provide this API"
        image_status_was_404=true
        image_status_404_count=$((image_status_404_count + 1))
      else
        error_text=$(http_error_text "$API_HTTP")
      fi
      status=error
    elif ! portainer_status=$(jq -er '.Status | select(type == "string")' "$status_body" 2>/dev/null); then
      error_text="invalid image-status JSON"
      status=error
    else
      error_text=""
      case $portainer_status in
        updated) status=updated ;;
        outdated) status=outdated ;;
        error)
          status=error
          error_text="Portainer reported image-status error"
          ;;
        *) status=unknown ;;
      esac
    fi
    if [[ $status == error ]]; then
      if [[ $image_status_was_404 == false || $image_status_404_reported == false ]]; then
        printf 'Environment %s, container %s: %s.\n' "$environment_name" "$container_name" "$error_text" >&2
      fi
      [[ $image_status_was_404 == false ]] || image_status_404_reported=true
    fi
    update_available=false
    [[ $status == outdated ]] && update_available=true
    if [[ $status == error ]]; then
      jq -cn --arg id "$container_id" --arg name "$container_name" --arg image "$image" --arg error "$error_text" \
        '{id:$id,name:$name,image:$image,status:"error",update_available:false,error:$error}' >> "$container_lines"
    else
      jq -cn --arg id "$container_id" --arg name "$container_name" --arg image "$image" --arg status "$status" --argjson update "$update_available" \
        '{id:$id,name:$name,image:$image,status:$status,update_available:$update,error:null}' >> "$container_lines"
    fi
  done < <(jq -c '.[]' "$list_body")

  containers=$(jq -s '.' "$container_lines")
  updates=$(jq '[.[] | select(.update_available == true)] | length' <<< "$containers")
  errors=$(jq '[.[] | select(.status == "error")] | length' <<< "$containers")
  environment_status=ok
  environment_error=""
  ((errors > 0)) && environment_status=warning
  if ((eligible_containers > 0 && image_status_404_count == eligible_containers)); then
    environment_status=error
    environment_error="image-status API unavailable for all containers; Portainer CE is not supported"
  fi
  jq -cn --arg id "$environment_id" --arg name "$environment_name" --arg status "$environment_status" \
    --arg environment_error "$environment_error" --argjson updates "$updates" --argjson errors "$errors" --argjson containers "$containers" \
    '{id:$id,name:$name,status:$status,updates:$updates,errors:$errors,containers:$containers,error:(if $environment_error == "" then null else $environment_error end)}' >> "$ENV_LINES"
done

environments=$(jq -s '.' "$ENV_LINES")
environment_count=$(jq 'length' <<< "$environments")
failed_environments=$(jq '[.[] | select(.status == "error")] | length' <<< "$environments")
total_updates=$(jq '[.[].updates] | add // 0' <<< "$environments")
total_errors=$(jq '[.[].errors] | add // 0' <<< "$environments")
overall_status=ok
if ((environment_count == 0 || failed_environments == environment_count)); then
  overall_status=error
elif ((total_errors > 0)); then
  overall_status=warning
fi

jq -cn --arg status "$overall_status" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total_updates "$total_updates" --argjson total_errors "$total_errors" --argjson environments "$environments" \
  '{status:$status,checked_at:$checked_at,total_updates:$total_updates,total_errors:$total_errors,environments:$environments}'

case $overall_status in
  ok) exit 0 ;;
  warning) exit 1 ;;
  *) exit 2 ;;
esac
