#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SCRIPT="$PROJECT_DIR/portainer_docker_updates.sh"
TEMPLATE="$PROJECT_DIR/template_portainer_docker_updates.yaml"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/portainer-updates-tests.XXXXXX")
SERVER_PID=""
PASS=0
FAIL=0

cleanup() {
  if [[ -n $SERVER_PID ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT HUP INT TERM

pass() {
  PASS=$((PASS + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'not ok - %s\n' "$1" >&2
}

assert_jq() {
  local description=$1 file=$2 expression=$3
  if jq -e "$expression" "$file" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
    jq . "$file" >&2 2>/dev/null || true
  fi
}

run_check() {
  local config=$1 output=$2 error=$3
  set +e
  PORTAINER_UPDATES_CONFIG="$config" "$SCRIPT" > "$output" 2> "$error"
  RUN_RC=$?
  set -e
  if jq empty "$output" >/dev/null 2>&1; then
    pass "output is valid JSON: $(basename "$config")"
  else
    fail "output is valid JSON: $(basename "$config")"
  fi
}

make_config() {
  local path=$1 url=$2 environments=$3 key_file=$4 extra=${5:-}
  {
    printf 'PORTAINER_URL=%q\n' "$url"
    printf 'PORTAINER_API_KEY_FILE=%q\n' "$key_file"
    printf 'PORTAINER_ENVIRONMENTS=%q\n' "$environments"
    printf '%s\n' 'VERIFY_TLS="true"' 'CA_FILE=""' 'CONNECT_TIMEOUT="2"' 'REQUEST_TIMEOUT="3"' 'INCLUDE_STOPPED="false"'
    printf '%s\n' 'CONTAINER_INCLUDE_REGEX=""' 'CONTAINER_EXCLUDE_REGEX=""' 'IMAGE_EXCLUDE_REGEX=""'
    [[ -z $extra ]] || printf '%s\n' "$extra"
  } > "$path"
  chmod 600 "$path"
}

start_mock_server() {
  local port_file="$TEST_DIR/port"
  command -v perl >/dev/null 2>&1 || { printf 'perl is required for the offline mock server.\n' >&2; exit 1; }
  perl -MIO::Socket::INET -e '
    use strict; use warnings;
    $SIG{TERM} = sub { exit 0 };
    my $server = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Proto => "tcp", Listen => 20, ReuseAddr => 1) or die $!;
    $| = 1; print $server->sockport, "\n";
    while (my $client = $server->accept) {
      $client->autoflush(1);
      my $request = <$client> // "";
      my ($path) = $request =~ m{^[A-Z]+\s+(\S+)};
      my $key = "";
      while (my $line = <$client>) {
        last if $line =~ /^\r?$/;
        $key = $1 if $line =~ /^X-API-Key:\s*(.*?)\r?$/i;
      }
      my ($code, $reason, $body) = (200, "OK", "{}");
      if ($key ne "test-key") {
        ($code, $reason, $body) = (401, "Unauthorized", q({"message":"Unauthorized"}));
      } elsif (($path // "") =~ m{/api/endpoints/1/docker/containers/json\?all=(true|false)}) {
        my $stopped = $1 eq "true" ? q(,{"Id":"c-stopped","Names":["/stopped"],"Image":"postgres:16","State":"exited"}) : "";
        $body = q([{"Id":"c-updated","Names":["/web"],"Image":"nginx:stable","State":"running"},{"Id":"c-outdated","Names":["/db"],"Image":"postgres:15","State":"running"},{"Id":"c-unknown","Names":["/worker"],"Image":"example/worker:latest","State":"running"},{"Id":"c-special","Names":["/strange name [prod] \"x\""],"Image":"registry.example/team/image:tag@sha256:abc","State":"running"},{"Id":"c-excluded","Names":["/skip-me"],"Image":"private.example/skip:latest","State":"running"}) . $stopped . q(]);
      } elsif (($path // "") =~ m{/api/endpoints/2/docker/containers/json}) {
        $body = "[]";
      } elsif (($path // "") =~ m{/api/endpoints/3/docker/containers/json}) {
        ($code, $reason, $body) = (500, "Internal Server Error", q({"message":"mock failure"}));
      } elsif (($path // "") =~ m{/api/endpoints/4/docker/containers/json}) {
        $body = "{not-json";
      } elsif (($path // "") =~ m{/api/endpoints/5/docker/containers/json}) {
        $body = q([{"Id":"c-no-status-1","Names":["/ce-one"],"Image":"nginx:latest","State":"running"},{"Id":"c-no-status-2","Names":["/ce-two"],"Image":"redis:latest","State":"running"}]);
      } elsif (($path // "") =~ m{/containers/c-updated/image_status}) {
        $body = q({"Status":"updated"});
      } elsif (($path // "") =~ m{/containers/c-outdated/image_status}) {
        $body = q({"Status":"outdated"});
      } elsif (($path // "") =~ m{/containers/c-unknown/image_status}) {
        $body = q({"Status":"future-status"});
      } elsif (($path // "") =~ m{/containers/c-special/image_status}) {
        $body = q({"Status":"updated"});
      } elsif (($path // "") =~ m{/containers/c-excluded/image_status}) {
        $body = q({"Status":"updated"});
      } elsif (($path // "") =~ m{/containers/c-stopped/image_status}) {
        $body = q({"Status":"outdated"});
      } else {
        ($code, $reason, $body) = (404, "Not Found", q({"message":"not found"}));
      }
      print $client "HTTP/1.1 $code $reason\r\nContent-Type: application/json\r\nContent-Length: " . length($body) . "\r\nConnection: close\r\n\r\n$body";
      close $client;
    }
  ' > "$port_file" &
  SERVER_PID=$!
  for _ in {1..100}; do
    [[ -s $port_file ]] && break
    sleep 0.05
  done
  [[ -s $port_file ]] || { printf 'Mock server failed to start.\n' >&2; exit 1; }
  MOCK_URL="http://127.0.0.1:$(<"$port_file")"
}

printf 'test-key\n' > "$TEST_DIR/key"
chmod 600 "$TEST_DIR/key"

if bash -n "$SCRIPT" && bash -n "$0"; then
  pass 'bash syntax'
else
  fail 'bash syntax'
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$SCRIPT" "$0"; then
    pass 'ShellCheck'
  else
    fail 'ShellCheck'
  fi
else
  printf 'ok - ShellCheck not installed (skipped)\n'
fi

if command -v ruby >/dev/null 2>&1; then
  if ruby -e 'require "yaml"; data=YAML.safe_load(File.read(ARGV[0]), aliases: false); abort unless data.dig("zabbix_export", "version") == "7.0"' "$TEMPLATE"; then
    pass 'template YAML parses and declares Zabbix 7.0'
  else
    fail 'template YAML parses and declares Zabbix 7.0'
  fi
else
  printf 'ok - Ruby YAML parser not installed (template parse skipped)\n'
fi

missing_config="$TEST_DIR/missing.conf"
run_check "$missing_config" "$TEST_DIR/out-missing-config" "$TEST_DIR/err-missing-config"
if [[ $RUN_RC -eq 2 ]]; then
  assert_jq 'missing configuration' "$TEST_DIR/out-missing-config" '.status == "error"'
else
  fail 'missing configuration exit code'
fi

make_config "$TEST_DIR/missing-key.conf" 'http://127.0.0.1:1' '1:docker01' "$TEST_DIR/no-key"
run_check "$TEST_DIR/missing-key.conf" "$TEST_DIR/out-missing-key" "$TEST_DIR/err-missing-key"
if [[ $RUN_RC -eq 2 ]]; then
  assert_jq 'missing API key file' "$TEST_DIR/out-missing-key" '.status == "error"'
else
  fail 'missing API key exit code'
fi

start_mock_server

make_config "$TEST_DIR/multiple.conf" "$MOCK_URL" '1:docker01,2:docker02' "$TEST_DIR/key"
run_check "$TEST_DIR/multiple.conf" "$TEST_DIR/out-multiple" "$TEST_DIR/err-multiple"
[[ $RUN_RC -eq 0 ]] || fail 'multiple environments exit code'
assert_jq 'multiple environments and empty list' "$TEST_DIR/out-multiple" '.status == "ok" and (.environments | length) == 2 and .environments[1].containers == []'
assert_jq 'updated status' "$TEST_DIR/out-multiple" '[.environments[0].containers[] | select(.id == "c-updated" and .status == "updated")] | length == 1'
assert_jq 'outdated status' "$TEST_DIR/out-multiple" '.total_updates == 1 and ([.environments[0].containers[] | select(.id == "c-outdated" and .status == "outdated" and .update_available)] | length == 1)'
assert_jq 'unknown Portainer status' "$TEST_DIR/out-multiple" '[.environments[0].containers[] | select(.id == "c-unknown" and .status == "unknown")] | length == 1'
assert_jq 'special characters preserved' "$TEST_DIR/out-multiple" '[.environments[0].containers[] | select(.id == "c-special" and .name == "strange name [prod] \"x\"")] | length == 1'
assert_jq 'stopped container omitted by default' "$TEST_DIR/out-multiple" '[.environments[0].containers[] | select(.id == "c-stopped")] | length == 0'

make_config "$TEST_DIR/stopped.conf" "$MOCK_URL" '1:docker01' "$TEST_DIR/key" 'INCLUDE_STOPPED="true"'
run_check "$TEST_DIR/stopped.conf" "$TEST_DIR/out-stopped" "$TEST_DIR/err-stopped"
assert_jq 'stopped container optionally included' "$TEST_DIR/out-stopped" '[.environments[0].containers[] | select(.id == "c-stopped" and .status == "outdated")] | length == 1'

make_config "$TEST_DIR/filter.conf" "$MOCK_URL" '1:docker01' "$TEST_DIR/key" $'CONTAINER_INCLUDE_REGEX="^(web|db|skip|strange)"\nCONTAINER_EXCLUDE_REGEX="^db$"\nIMAGE_EXCLUDE_REGEX="^private\\.example/"'
run_check "$TEST_DIR/filter.conf" "$TEST_DIR/out-filter" "$TEST_DIR/err-filter"
assert_jq 'include and exclude filters' "$TEST_DIR/out-filter" '([.environments[0].containers[] | select(.status == "excluded")] | length) == 3 and .total_updates == 0'

printf 'bad-key\n' > "$TEST_DIR/bad-key"
make_config "$TEST_DIR/auth.conf" "$MOCK_URL" '1:docker01' "$TEST_DIR/bad-key"
run_check "$TEST_DIR/auth.conf" "$TEST_DIR/out-auth" "$TEST_DIR/err-auth"
[[ $RUN_RC -eq 2 ]] || fail 'invalid authentication exit code'
assert_jq 'invalid authentication' "$TEST_DIR/out-auth" '.status == "error" and .total_errors == 1'
if ! grep -F 'bad-key' "$TEST_DIR/out-auth" "$TEST_DIR/err-auth" >/dev/null; then pass 'API key is not leaked'; else fail 'API key is not leaked'; fi

make_config "$TEST_DIR/http.conf" "$MOCK_URL" '3:broken' "$TEST_DIR/key"
run_check "$TEST_DIR/http.conf" "$TEST_DIR/out-http" "$TEST_DIR/err-http"
assert_jq 'HTTP error' "$TEST_DIR/out-http" '.status == "error" and .environments[0].status == "error"'

make_config "$TEST_DIR/ce-endpoint.conf" "$MOCK_URL" '5:portainer-ce' "$TEST_DIR/key"
run_check "$TEST_DIR/ce-endpoint.conf" "$TEST_DIR/out-ce-endpoint" "$TEST_DIR/err-ce-endpoint"
[[ $RUN_RC -eq 2 ]] || fail 'unavailable image-status API exit code'
assert_jq 'unavailable image-status API marks environment failed' "$TEST_DIR/out-ce-endpoint" '.status == "error" and .environments[0].status == "error" and .environments[0].errors == 2 and (.environments[0].error | contains("Portainer CE"))'
if [[ $(grep -c 'image-status endpoint unavailable' "$TEST_DIR/err-ce-endpoint") -eq 1 ]]; then
  pass 'unavailable endpoint diagnostic is emitted once per environment'
else
  fail 'unavailable endpoint diagnostic is emitted once per environment'
fi

make_config "$TEST_DIR/json.conf" "$MOCK_URL" '4:invalid-json' "$TEST_DIR/key"
run_check "$TEST_DIR/json.conf" "$TEST_DIR/out-json" "$TEST_DIR/err-json"
assert_jq 'invalid JSON' "$TEST_DIR/out-json" '.status == "error" and .environments[0].error == "invalid container-list JSON"'

make_config "$TEST_DIR/partial.conf" "$MOCK_URL" '1:docker01,3:broken' "$TEST_DIR/key"
run_check "$TEST_DIR/partial.conf" "$TEST_DIR/out-partial" "$TEST_DIR/err-partial"
[[ $RUN_RC -eq 1 ]] || fail 'partial failure exit code'
assert_jq 'partial environment failure' "$TEST_DIR/out-partial" '.status == "warning" and .total_errors == 1 and .environments[0].status == "ok" and .environments[1].status == "error"'

make_config "$TEST_DIR/unreachable.conf" 'http://127.0.0.1:1' '1:offline' "$TEST_DIR/key"
run_check "$TEST_DIR/unreachable.conf" "$TEST_DIR/out-unreachable" "$TEST_DIR/err-unreachable"
assert_jq 'unreachable Portainer' "$TEST_DIR/out-unreachable" '.status == "error" and .environments[0].error == "connection failed"'

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
