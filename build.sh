#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${ROOT_DIR}/dist"

log() {
  printf '[build.sh] %s\n' "$*"
}

die() {
  printf '[build.sh] Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./build.sh package   Create a production bundle in ./dist
  ./build.sh up        Build and start the production stack from the current directory
  ./build.sh down      Stop the production stack from the current directory
  ./build.sh restart   Restart the production stack from the current directory
  ./build.sh logs      Tail production logs from the current directory
  ./build.sh ps        Show production container status from the current directory

Notes:
  - Run `./build.sh package` in the source repository to create dist/.
  - Copy the contents of dist/ to the server.
  - On the server, edit `.env` and `configs/exampleconfig_secret.json` if needed,
    then run `./build.sh up`.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ensure_source_layout() {
  [[ -f "${ROOT_DIR}/docker-compose.yml" ]] || die "docker-compose.yml not found"
  [[ -f "${ROOT_DIR}/docker-compose.tests.yml" ]] || die "This command must be run from the source repository"
  [[ -d "${ROOT_DIR}/configs" ]] || die "configs directory not found"
  [[ -d "${ROOT_DIR}/docker" ]] || die "docker directory not found"
  [[ -f "${ROOT_DIR}/tests/requirements.txt" ]] || die "tests/requirements.txt not found"
}

ensure_runtime_layout() {
  [[ -f "${ROOT_DIR}/docker-compose.yml" ]] || die "docker-compose.yml not found in current directory"
  [[ -d "${ROOT_DIR}/configs" ]] || die "configs directory not found in current directory"
  [[ -d "${ROOT_DIR}/docker" ]] || die "docker directory not found in current directory"
  [[ -f "${ROOT_DIR}/tests/requirements.txt" ]] || die "tests/requirements.txt not found in current directory"
  [[ -f "${ROOT_DIR}/user_data/config.json" ]] || die "user_data/config.json not found in current directory"
  [[ -f "${ROOT_DIR}/user_data/strategies/NostalgiaForInfinityX7.py" ]] || \
    die "user_data/strategies/NostalgiaForInfinityX7.py not found in current directory"
}

copy_file_if_exists() {
  local src="$1"
  local dest="$2"

  if [[ -f "${src}" ]]; then
    cp "${src}" "${dest}"
  fi
}

prepare_dist_layout() {
  rm -rf "${DIST_DIR}"

  mkdir -p \
    "${DIST_DIR}/configs" \
    "${DIST_DIR}/docker" \
    "${DIST_DIR}/tests" \
    "${DIST_DIR}/user_data/data" \
    "${DIST_DIR}/user_data/logs" \
    "${DIST_DIR}/user_data/backtest_results" \
    "${DIST_DIR}/user_data/freqaimodels" \
    "${DIST_DIR}/user_data/hyperopt_results" \
    "${DIST_DIR}/user_data/hyperopts" \
    "${DIST_DIR}/user_data/notebooks" \
    "${DIST_DIR}/user_data/plot" \
    "${DIST_DIR}/user_data/strategies"
}

copy_runtime_files() {
  cp -R "${ROOT_DIR}/configs/." "${DIST_DIR}/configs/"
  cp -R "${ROOT_DIR}/docker/." "${DIST_DIR}/docker/"
  cp "${ROOT_DIR}/tests/requirements.txt" "${DIST_DIR}/tests/requirements.txt"
  cp "${ROOT_DIR}/README.md" "${DIST_DIR}/README.md"
  cp "${ROOT_DIR}/live-account-example.env" "${DIST_DIR}/.env.example"
  cp "${ROOT_DIR}/build.sh" "${DIST_DIR}/build.sh"

  if [[ -f "${ROOT_DIR}/.env" ]]; then
    cp "${ROOT_DIR}/.env" "${DIST_DIR}/.env"
  else
    cp "${ROOT_DIR}/live-account-example.env" "${DIST_DIR}/.env"
  fi

  if [[ -f "${ROOT_DIR}/user_data/config.json" ]]; then
    cp "${ROOT_DIR}/user_data/config.json" "${DIST_DIR}/user_data/config.json"
  else
    cp "${ROOT_DIR}/configs/recommended_config.json" "${DIST_DIR}/user_data/config.json"
  fi

  copy_file_if_exists "${ROOT_DIR}/user_data/config-private.json" "${DIST_DIR}/user_data/config-private.json"
  copy_file_if_exists "${ROOT_DIR}/user_data/config.json.bak" "${DIST_DIR}/user_data/config.json.bak"
  [[ -f "${ROOT_DIR}/NostalgiaForInfinityX7.py" ]] || die "NostalgiaForInfinityX7.py not found"
  cp "${ROOT_DIR}/NostalgiaForInfinityX7.py" \
    "${DIST_DIR}/user_data/strategies/NostalgiaForInfinityX7.py"

  : >"${DIST_DIR}/user_data/logs/.gitkeep"
  : >"${DIST_DIR}/user_data/backtest_results/.gitkeep"
}

write_production_compose() {
  cat >"${DIST_DIR}/docker-compose.yml" <<'EOF'
---

x-common-settings:
  &common-settings
  image: freqtradeorg/freqtrade:stable
  build:
    context: .
    dockerfile: "./docker/Dockerfile.custom"
  restart: unless-stopped
  volumes:
    - "./user_data:/freqtrade/user_data"
    - "./user_data/data:/freqtrade/user_data/data"
    - "./configs:/freqtrade/configs"
    - "./user_data/strategies/${FREQTRADE__STRATEGY:-NostalgiaForInfinityX7}.py:/freqtrade/user_data/strategies/${FREQTRADE__STRATEGY:-NostalgiaForInfinityX7}.py"
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:${FREQTRADE__API_SERVER__LISTEN_PORT:-8080}"]
    interval: 1m30s
    timeout: 10s
    retries: 3
    start_period: 40s
    start_interval: 5s
  env_file:
    - path: .env
      required: false

services:
  freqtrade:
    <<: *common-settings
    container_name: ${FREQTRADE__BOT_NAME:-Example_Test_Account}_${FREQTRADE__EXCHANGE__NAME:-binance}_${FREQTRADE__TRADING_MODE:-futures}-${FREQTRADE__STRATEGY:-NostalgiaForInfinityX7}
    ports:
      - "${FREQTRADE__API_SERVER__LISTEN_PORT:-8080}:${FREQTRADE__API_SERVER__LISTEN_PORT:-8080}"
    command: >
      trade
      --db-url sqlite:////freqtrade/user_data/${FREQTRADE__BOT_NAME:-Example_Test_Account}_${FREQTRADE__EXCHANGE__NAME:-binance}_${FREQTRADE__TRADING_MODE:-futures}-tradesv3.sqlite
      --log-file user_data/logs/${FREQTRADE__BOT_NAME:-Example_Test_Account}-${FREQTRADE__EXCHANGE__NAME:-binance}-${FREQTRADE__STRATEGY:-NostalgiaForInfinityX7}-${FREQTRADE__TRADING_MODE:-futures}.log
      --strategy-path /freqtrade/user_data/strategies
EOF
}

write_deploy_notes() {
  cat >"${DIST_DIR}/DEPLOY.md" <<'EOF'
# Production Bundle

## First-time setup
1. Review and edit `.env`
2. Review and edit `configs/exampleconfig_secret.json`
3. Optionally adjust `user_data/config.json`

## Runtime commands
```bash
./build.sh up
./build.sh logs
./build.sh ps
./build.sh down
```

## Direct Docker Compose usage
```bash
docker compose up -d --build
docker compose logs -f --tail=200
docker compose ps
docker compose down
```
EOF
}

package_dist() {
  ensure_source_layout
  prepare_dist_layout
  copy_runtime_files
  write_production_compose
  write_deploy_notes
  chmod +x "${DIST_DIR}/build.sh"

  log "Production bundle created at ${DIST_DIR}"
  log "Copy the contents of dist/ to your server, then run ./build.sh up there."
}

run_compose() {
  require_command docker
  ensure_runtime_layout

  case "${1}" in
    up)
      docker compose up -d --build
      ;;
    down)
      docker compose down
      ;;
    restart)
      docker compose down
      docker compose up -d --build
      ;;
    logs)
      docker compose logs -f --tail=200
      ;;
    ps)
      docker compose ps
      ;;
    *)
      die "Unsupported runtime command: ${1}"
      ;;
  esac
}

main() {
  local command="${1:-package}"

  case "${command}" in
    package)
      package_dist
      ;;
    up|down|restart|logs|ps)
      run_compose "${command}"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      die "Unknown command: ${command}"
      ;;
  esac
}

main "$@"
