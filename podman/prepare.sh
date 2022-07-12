#!/usr/bin/bash
# https://docs.gitlab.com/runner/executors/custom.html#prepare

# shellcheck source=./include.sh
source "${BASH_SOURCE[0]%/*}/include.sh"


ensure_executable_available podman


# Create CI WorkSpace path if it doesn't exist
if [[ ! -d "${CI_WS}" ]]; then
    mkdir -p "${CI_WS}"
fi


echo -e "Preparing the container ${CONTAINER_NAME}."

# Check if CI job image is set
if [[ -z "${CUSTOM_ENV_CI_JOB_IMAGE}" ]]; then
    die "No CI job image specified"
fi
# Make sure the (temporary) directory for the container exists.
mkdir -p "${CONTAINER_WS}"

mkdir -p "${CONTAINER_BUILDS_DIR}"

#mkdir -p "${CONTAINER_CACHE_DIR}"

mkdir -p "${CONTAINER_SCRIPT_DIR}"
mkdir -p "${CONTAINER_STEPS_DIR}"

mkdir -p "${SLURM_IDS_PATH}"


# Image is needed in the login node anyway, might as well pull it to see if
# there are problems
COMMAND=(
    podman pull \
        "${CUSTOM_ENV_CI_JOB_IMAGE}"
)
"${COMMAND[@]}" || die "Command: ${COMMAND[*]} failed with exit code ${?}"

