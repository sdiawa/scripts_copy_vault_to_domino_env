#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
DOMINO_PROJECT_NAME="${2:-}"
VAULT_COS_NAME="${3:-}"
AP_CODE="${4:-}"
VAULT_NAMESPACE="${5:-}"
VAULT_ENV="${6:-}"

VAULT_ACCESS_KEY_NAME="COS_HMAC_KEYS_ACCESS_KEY_ID_READER"
VAULT_SECRET_KEY_NAME="COS_HMAC_KEYS_SECRET_ACCESS_KEY_READER"

DOMINO_ACCESS_VAR_NAME="COS_API_ID_KEY_READER_${AP_CODE}"
DOMINO_SECRET_VAR_NAME="COS_API_SECRET_KEY_READER_${AP_CODE}"

VAULT_PATH="Secret/objsto/${VAULT_COS_NAME}"
DOTENV_FILE="secrets.env"

VAULT_ADDR=""
VAULT_TOKEN=""

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo ""
  echo "ERROR: $*" >&2
  echo ""
  exit 1
}

usage() {
  echo "Usage:"
  echo "  $0 validate <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>"
  echo "  $0 fetch    <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>"
  echo "  $0 inject   <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>"
  echo ""
  echo "VAULT_ENV accepted values:"
  echo "  HPROD-A"
  echo "  HPROD-B"
  echo "  PROD-A"
  echo "  PROD-B"
  exit 1
}

check_args() {
  [[ -n "${ACTION}" ]] || usage
  [[ -n "${DOMINO_PROJECT_NAME}" ]] || error "DOMINO_PROJECT_NAME is required"
  [[ -n "${VAULT_COS_NAME}" ]] || error "VAULT_COS_NAME is required"
  [[ -n "${AP_CODE}" ]] || error "AP_CODE is required"
  [[ -n "${VAULT_NAMESPACE}" ]] || error "VAULT_NAMESPACE is required"
  [[ -n "${VAULT_ENV}" ]] || error "VAULT_ENV is required"

  case "${ACTION}" in
    validate|fetch|inject) ;;
    *) usage ;;
  esac

  case "${VAULT_ENV}" in
    HPROD-A|HPROD-B|PROD-A|PROD-B) ;;
    *) error "VAULT_ENV invalide: ${VAULT_ENV}. Valeurs acceptées: HPROD-A, HPROD-B, PROD-A, PROD-B" ;;
  esac
}

resolve_vault_config() {
  case "${VAULT_ENV}" in
    HPROD-A)
      VAULT_ADDR="${VAULT_URL_HPROD_A:-}"
      VAULT_TOKEN="${VAULT_TOKEN_HPROD_A:-}"
      ;;
    HPROD-B)
      VAULT_ADDR="${VAULT_URL_HPROD_B:-}"
      VAULT_TOKEN="${VAULT_TOKEN_HPROD_B:-}"
      ;;
    PROD-A)
      VAULT_ADDR="${VAULT_URL_PROD_A:-}"
      VAULT_TOKEN="${VAULT_TOKEN_PROD_A:-}"
      ;;
    PROD-B)
      VAULT_ADDR="${VAULT_URL_PROD_B:-}"
      VAULT_TOKEN="${VAULT_TOKEN_PROD_B:-}"
      ;;
  esac

  [[ -n "${VAULT_ADDR}" ]] || error "URL Vault non configurée pour VAULT_ENV=${VAULT_ENV}"
  [[ -n "${VAULT_TOKEN}" ]] || error "Token Vault non configuré pour VAULT_ENV=${VAULT_ENV}"
}

check_required_env() {
  [[ -n "${DOMINO_URL:-}" ]] || error "DOMINO_URL is not set"
  [[ -n "${DOMINO_API_KEY:-}" ]] || error "DOMINO_API_KEY is not set"

  if [[ "${ACTION}" == "validate" || "${ACTION}" == "fetch" ]]; then
    resolve_vault_config
  fi
}

domino_get_project_id() {
  local project_name="$1"

  local response
  response=$(curl --silent --show-error --fail \
    --header "X-Domino-Api-Key: ${DOMINO_API_KEY}" \
    "${DOMINO_URL}/v4/projects")

  local project_id
  project_id=$(echo "${response}" | jq -r ".[] | select(.name == \"${project_name}\") | .id")

  [[ -n "${project_id}" && "${project_id}" != "null" ]] || error "Projet Domino introuvable: ${project_name}"

  echo "${project_id}"
}

vault_check_secret_exists() {
  local vault_path="$1"

  local http_code
  http_code=$(curl --silent --output /tmp/vault_check_response.json --write-out "%{http_code}" \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --header "X-Vault-Namespace: ${VAULT_NAMESPACE}" \
    "${VAULT_ADDR}/v1/${vault_path}")

  [[ "${http_code}" == "200" ]] || error "Path Vault introuvable ou inaccessible: ${vault_path} sur ${VAULT_ENV}"
}

vault_read_secret_value() {
  local vault_path="$1"
  local key_name="$2"

  local response
  response=$(curl --silent --show-error --fail \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --header "X-Vault-Namespace: ${VAULT_NAMESPACE}" \
    "${VAULT_ADDR}/v1/${vault_path}")

  echo "${response}" | jq -r ".data.data[\"${key_name}\"] // .data[\"${key_name}\"] // empty"
}

domino_env_var_exists() {
  local project_id="$1"
  local var_name="$2"

  local response
  response=$(curl --silent --show-error --fail \
    --header "X-Domino-Api-Key: ${DOMINO_API_KEY}" \
    "${DOMINO_URL}/v4/projects/${project_id}/environmentVariables")

  local found
  found=$(echo "${response}" | jq -r ".[] | select(.name == \"${var_name}\") | .id")

  [[ -n "${found}" && "${found}" != "null" ]]
}

domino_create_env_var() {
  local project_id="$1"
  local var_name="$2"
  local var_value="$3"

  if domino_env_var_exists "${project_id}" "${var_name}"; then
    error "La variable ${var_name} existe déjà dans Domino. Supprime-la manuellement depuis Domino puis relance le job."
  fi

  log "Création de la variable Domino: ${var_name}"

  curl --silent --show-error --fail --request POST \
    --header "X-Domino-Api-Key: ${DOMINO_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "$(jq -n \
      --arg name "${var_name}" \
      --arg value "${var_value}" \
      '{
        name: $name,
        value: $value,
        isSecret: true
      }')" \
    "${DOMINO_URL}/v4/projects/${project_id}/environmentVariables" >/dev/null
}

validate() {
  log "========== VALIDATE =========="
  log "Projet Domino   : ${DOMINO_PROJECT_NAME}"
  log "Vault COS       : ${VAULT_COS_NAME}"
  log "Vault path      : ${VAULT_PATH}"
  log "Vault namespace : ${VAULT_NAMESPACE}"
  log "Vault env       : ${VAULT_ENV}"
  log "AP code         : ${AP_CODE}"

  local project_id
  project_id=$(domino_get_project_id "${DOMINO_PROJECT_NAME}")
  log "Projet Domino trouvé: ${project_id}"

  vault_check_secret_exists "${VAULT_PATH}"
  log "Path Vault trouvé: ${VAULT_PATH}"

  local access_key
  local secret_key

  access_key=$(vault_read_secret_value "${VAULT_PATH}" "${VAULT_ACCESS_KEY_NAME}")
  secret_key=$(vault_read_secret_value "${VAULT_PATH}" "${VAULT_SECRET_KEY_NAME}")

  [[ -n "${access_key}" ]] || error "Secret Vault manquant: ${VAULT_ACCESS_KEY_NAME}"
  [[ -n "${secret_key}" ]] || error "Secret Vault manquant: ${VAULT_SECRET_KEY_NAME}"

  log "Secret Vault trouvé: ${VAULT_ACCESS_KEY_NAME}"
  log "Secret Vault trouvé: ${VAULT_SECRET_KEY_NAME}"

  if domino_env_var_exists "${project_id}" "${DOMINO_ACCESS_VAR_NAME}"; then
    error "La variable ${DOMINO_ACCESS_VAR_NAME} existe déjà dans Domino. Supprime-la manuellement puis relance le pipeline."
  fi

  if domino_env_var_exists "${project_id}" "${DOMINO_SECRET_VAR_NAME}"; then
    error "La variable ${DOMINO_SECRET_VAR_NAME} existe déjà dans Domino. Supprime-la manuellement puis relance le pipeline."
  fi

  log "Les variables Domino n'existent pas encore."
  log "Validation OK."
}

fetch() {
  log "========== FETCH VAULT =========="

  local project_id
  project_id=$(domino_get_project_id "${DOMINO_PROJECT_NAME}")

  local access_key
  local secret_key

  access_key=$(vault_read_secret_value "${VAULT_PATH}" "${VAULT_ACCESS_KEY_NAME}")
  secret_key=$(vault_read_secret_value "${VAULT_PATH}" "${VAULT_SECRET_KEY_NAME}")

  [[ -n "${access_key}" ]] || error "Secret Vault manquant: ${VAULT_ACCESS_KEY_NAME}"
  [[ -n "${secret_key}" ]] || error "Secret Vault manquant: ${VAULT_SECRET_KEY_NAME}"

  cat > "${DOTENV_FILE}" <<EOF
PROJECT_ID=${project_id}
ACCESS_VAR_NAME=${DOMINO_ACCESS_VAR_NAME}
SECRET_VAR_NAME=${DOMINO_SECRET_VAR_NAME}
ACCESS_KEY=${access_key}
SECRET_KEY=${secret_key}
EOF

  log "Fichier ${DOTENV_FILE} généré."
}

inject() {
  log "========== INJECT DOMINO =========="

  [[ -n "${PROJECT_ID:-}" ]] || error "PROJECT_ID manquant. Vérifie l'artifact dotenv du stage fetch."
  [[ -n "${ACCESS_VAR_NAME:-}" ]] || error "ACCESS_VAR_NAME manquant."
  [[ -n "${SECRET_VAR_NAME:-}" ]] || error "SECRET_VAR_NAME manquant."
  [[ -n "${ACCESS_KEY:-}" ]] || error "ACCESS_KEY manquant."
  [[ -n "${SECRET_KEY:-}" ]] || error "SECRET_KEY manquant."

  log "Projet Domino ID: ${PROJECT_ID}"

  domino_create_env_var "${PROJECT_ID}" "${ACCESS_VAR_NAME}" "${ACCESS_KEY}"
  domino_create_env_var "${PROJECT_ID}" "${SECRET_VAR_NAME}" "${SECRET_KEY}"

  log "Injection terminée avec succès."
}

main() {
  check_args
  check_required_env

  case "${ACTION}" in
    validate)
      validate
      ;;
    fetch)
      fetch
      ;;
    inject)
      inject
      ;;
  esac
}

main
