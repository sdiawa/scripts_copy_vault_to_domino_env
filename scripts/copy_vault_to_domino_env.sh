#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
DOMINO_PROJECT_NAME="${2:-}"
VAULT_COS_NAME="${3:-}"
AP_CODE="${4:-}"
VAULT_NAMESPACE="${5:-}"
VAULT_ENV="${6:-}"

VAULT_ENGINE="objsto"
VAULT_API_PATH="${VAULT_ENGINE}/data/${VAULT_COS_NAME}"

VAULT_ACCESS_KEY_NAME="cos_hmac_keys_access_key_id_reader"
VAULT_SECRET_KEY_NAME="cos_hmac_keys_secret_access_key_reader"

DOMINO_ACCESS_VAR_NAME="COS_API_ID_KEY_READER_${AP_CODE}"
DOMINO_SECRET_VAR_NAME="COS_API_SECRET_KEY_READER_${AP_CODE}"

DOTENV_FILE="secrets.env"

VAULT_ADDR=""
VAULT_TOKEN=""

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO  $*"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN  $*" >&2
}

error() {
  echo ""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR $*" >&2
  echo ""
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 validate <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>
  $0 fetch    <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>
  $0 inject   <DOMINO_PROJECT_NAME> <VAULT_COS_NAME> <AP_CODE> <VAULT_NAMESPACE> <VAULT_ENV>

VAULT_ENV accepted values:
  HPROD-A
  HPROD-B
  PROD-A
  PROD-B
EOF
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

  [[ -n "${VAULT_ADDR}" ]] || error "URL Vault non configurée pour ${VAULT_ENV}"
  [[ -n "${VAULT_TOKEN}" ]] || error "Token Vault non configuré pour ${VAULT_ENV}"

  VAULT_ADDR="${VAULT_ADDR%/}"
}

check_required_env() {
  [[ -n "${DOMINO_URL:-}" ]] || error "DOMINO_URL is not set"
  [[ -n "${DOMINO_API_KEY:-}" ]] || error "DOMINO_API_KEY is not set"

  DOMINO_URL="${DOMINO_URL%/}"

  if [[ "${ACTION}" == "validate" || "${ACTION}" == "fetch" ]]; then
    resolve_vault_config
  fi
}

domino_get_project_id() {
  local project_name="$1"
  local response
  local project_id

  response=$(curl --silent --show-error --fail \
    --header "X-Domino-Api-Key: ${DOMINO_API_KEY}" \
    "${DOMINO_URL}/v4/projects") \
    || error "Impossible de récupérer la liste des projets Domino"

  project_id=$(echo "${response}" | jq -r ".[] | select(.name == \"${project_name}\") | .id" | head -n 1)

  [[ -n "${project_id}" && "${project_id}" != "null" ]] \
    || error "Projet Domino introuvable: ${project_name}"

  echo "${project_id}"
}

vault_check_secret_exists() {
  local http_code

  http_code=$(curl --silent --output /tmp/vault_check_response.json --write-out "%{http_code}" -X GET \
    "${VAULT_ADDR}/v1/${VAULT_API_PATH}" \
    -H "accept: application/json" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "X-Vault-Namespace: ${VAULT_NAMESPACE}")

  [[ "${http_code}" == "200" ]] \
    || error "Secret Vault introuvable ou inaccessible: ${VAULT_API_PATH} sur ${VAULT_ENV}. HTTP=${http_code}"
}

vault_read_secret_value() {
  local key_name="$1"
  local response
  local value

  response=$(curl --silent --show-error --fail -X GET \
    "${VAULT_ADDR}/v1/${VAULT_API_PATH}" \
    -H "accept: application/json" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "X-Vault-Namespace: ${VAULT_NAMESPACE}") \
    || error "Impossible de lire le secret Vault: ${VAULT_API_PATH}"

  value=$(echo "${response}" | jq -r ".data.data[\"${key_name}\"] // empty")

  [[ -n "${value}" ]] || error "Clé Vault manquante: ${key_name}"

  echo "${value}"
}

<!-- domino_env_var_exists() {
  local project_id="$1"
  local var_name="$2"
  local response
  local found

  response=$(curl --silent --show-error --fail \
    --header "X-Domino-Api-Key: ${DOMINO_API_KEY}" \
    "${DOMINO_URL}/v4/projects/${project_id}/environmentVariables") \
    || error "Impossible de lire les variables Domino du projet ${project_id}"

  found=$(echo "${response}" | jq -r ".[] | select(.name == \"${var_name}\") | .id" | head -n 1)

  [[ -n "${found}" && "${found}" != "null" ]]
} -->

domino_env_var_exists() {
  local project_id="$1"
  local var_name="$2"

  local response
  response=$(curl --silent --show-error --fail \
    --header "X-Domino-Api-Key: ${DOMINO_PROJECT_KEY}" \
    "${DOMINO_URL}/v4/projects/${project_id}/environmentVariables") \
    || error "Impossible de lire les variables Domino du projet ${project_id}"

  echo "${response}" | jq -e --arg name "${var_name}" '
    .[]
    | select(
        (.name // .key // .variableName // "") == $name
      )
  ' >/dev/null
}

domino_create_env_var() {
  local project_id="$1"
  local var_name="$2"
  local var_value="$3"

  if domino_env_var_exists "${project_id}" "${var_name}"; then
    error "La variable ${var_name} existe déjà dans Domino. Supprime-la manuellement depuis Domino puis relance le pipeline."
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
    "${DOMINO_URL}/v4/projects/${project_id}/environmentVariables" >/dev/null \
    || error "Échec création variable Domino: ${var_name}"
}

write_dotenv() {
  local project_id="$1"
  local access_key="$2"
  local secret_key="$3"

  cat > "${DOTENV_FILE}" <<EOF
PROJECT_ID=${project_id}
ACCESS_VAR_NAME=${DOMINO_ACCESS_VAR_NAME}
SECRET_VAR_NAME=${DOMINO_SECRET_VAR_NAME}
ACCESS_KEY=${access_key}
SECRET_KEY=${secret_key}
EOF

  chmod 600 "${DOTENV_FILE}"
}

validate() {
  log "========== VALIDATE =========="
  log "Projet Domino   : ${DOMINO_PROJECT_NAME}"
  log "Vault COS       : ${VAULT_COS_NAME}"
  log "Vault API path  : ${VAULT_API_PATH}"
  log "Vault namespace : ${VAULT_NAMESPACE}"
  log "Vault env       : ${VAULT_ENV}"
  log "AP code         : ${AP_CODE}"

  local project_id
  local access_key
  local secret_key

  project_id=$(domino_get_project_id "${DOMINO_PROJECT_NAME}")
  log "Projet Domino trouvé: ${project_id}"

  vault_check_secret_exists
  log "Secret Vault trouvé: ${VAULT_API_PATH}"

  access_key=$(vault_read_secret_value "${VAULT_ACCESS_KEY_NAME}")
  secret_key=$(vault_read_secret_value "${VAULT_SECRET_KEY_NAME}")

  [[ -n "${access_key}" ]] || error "Secret Vault vide: ${VAULT_ACCESS_KEY_NAME}"
  [[ -n "${secret_key}" ]] || error "Secret Vault vide: ${VAULT_SECRET_KEY_NAME}"

  log "Clé Vault trouvée: ${VAULT_ACCESS_KEY_NAME}"
  log "Clé Vault trouvée: ${VAULT_SECRET_KEY_NAME}"

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
  local access_key
  local secret_key

  project_id=$(domino_get_project_id "${DOMINO_PROJECT_NAME}")

  vault_check_secret_exists

  access_key=$(vault_read_secret_value "${VAULT_ACCESS_KEY_NAME}")
  secret_key=$(vault_read_secret_value "${VAULT_SECRET_KEY_NAME}")

  write_dotenv "${project_id}" "${access_key}" "${secret_key}"

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
