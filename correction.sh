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
