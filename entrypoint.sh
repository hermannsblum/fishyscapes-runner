#!/usr/bin/dumb-init /bin/bash

export RUNNER_ALLOW_RUNASROOT=1
export PATH=$PATH:/actions-runner

deregister_runner() {
  echo "Caught SIGTERM. Deregistering runner"
  _TOKEN=$(bash /token.sh)
  RUNNER_TOKEN=$(echo "${_TOKEN}" | jq -r .token)
  ./config.sh remove --token "${RUNNER_TOKEN}"
  exit
}

execute_docker_command() {
  "$@" 
}

_DISABLE_AUTOMATIC_DEREGISTRATION=${DISABLE_AUTOMATIC_DEREGISTRATION:-false}

_RUNNER_NAME=${RUNNER_NAME:-${RUNNER_NAME_PREFIX:-github-runner}-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')}
_RUNNER_WORKDIR=${RUNNER_WORKDIR:-/_work}
_LABELS=${LABELS:-default}
_RUNNER_GROUP=${RUNNER_GROUP:-Default}
_GITHUB_HOST=${GITHUB_HOST:="github.com"}

# ensure backwards compatibility
if [[ -z $RUNNER_SCOPE ]]; then
  if [[ ${ORG_RUNNER} == "true" ]]; then
    echo 'ORG_RUNNER is now deprecated. Please use RUNNER_SCOPE="org" instead.'
    export RUNNER_SCOPE="org"
  else
    export RUNNER_SCOPE="repo"
  fi
fi

RUNNER_SCOPE="${RUNNER_SCOPE,,}" # to lowercase

case ${RUNNER_SCOPE} in
  org*)
    [[ -z ${ORG_NAME} ]] && ( echo "ORG_NAME required for org runners"; exit 1 )
    _SHORT_URL="https://${_GITHUB_HOST}/${ORG_NAME}"
    RUNNER_SCOPE="org"
    ;;

  ent*)
    [[ -z ${ENTERPRISE_NAME} ]] && ( echo "ENTERPRISE_NAME required for enterprise runners"; exit 1 )
    _SHORT_URL="https://${_GITHUB_HOST}/enterprises/${ENTERPRISE_NAME}"
    RUNNER_SCOPE="enterprise"
    ;;

  *)
    [[ -z ${REPO_URL} ]] && ( echo "REPO_URL required for repo runners"; exit 1 )
    _SHORT_URL=${REPO_URL}
    RUNNER_SCOPE="repo"
    ;;
esac

# If the variable is not set, set it with the default value
if [ -z "${CONFIGURED_ACTIONS_RUNNER_FILES_DIR}" ]; then
  CONFIGURED_ACTIONS_RUNNER_FILES_DIR="/actions-runner-files"
fi

# Loading the files from the mounted directory
if [ -d "${CONFIGURED_ACTIONS_RUNNER_FILES_DIR}" ]; then
  cp -p -r "${CONFIGURED_ACTIONS_RUNNER_FILES_DIR}/." "/actions-runner"
fi

if [ -f "/actions-runner/.runner" ]; then
  echo "The runner has already been configured"
  unset ACCESS_TOKEN
  unset RUNNER_TOKEN
  execute_docker_command "$@"
  exit 0
fi

if [[ -n "${ACCESS_TOKEN}" ]]; then
  _TOKEN=$(bash /token.sh)
  RUNNER_TOKEN=$(echo "${_TOKEN}" | jq -r .token)
fi

echo "Configuring"
./config.sh \
    --url "${_SHORT_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${_RUNNER_NAME}" \
    --work "${_RUNNER_WORKDIR}" \
    --labels "${_LABELS}" \
    --runnergroup "${_RUNNER_GROUP}" \
    --unattended \
    --replace

unset RUNNER_TOKEN

# Saving the files in another directory for the possibility to mount them from the host next time
if [ -d "${CONFIGURED_ACTIONS_RUNNER_FILES_DIR}" ]; then
  # Quoting (even with double-quotes) the regexp brokes the copying
  cp -p -r "/actions-runner/_diag" "/actions-runner/svc.sh" /actions-runner/.[^.]* "${CONFIGURED_ACTIONS_RUNNER_FILES_DIR}"
fi

if [[ ${_DISABLE_AUTOMATIC_DEREGISTRATION} == "false" ]]; then
  trap deregister_runner SIGINT SIGQUIT SIGTERM
fi

execute_docker_command "$@"
