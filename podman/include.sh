#!/usr/bin/bash

# Include the slurm utility functions
# shellcheck source=./slurm_utils.sh
source "${BASH_SOURCE[0]%/*}/slurm_utils.sh"

# Do NOT touch these and make sure they are the same as local environment
# variables!! Otherwise, there can be *duplicate* locations and local containers
# will not see the same as gitlab containers!
export CI_WS="${CUSTOM_ENV_CI_WS}"
export SLURM_IDS_PATH="${CI_WS}/SLURM_IDS"
export LOGFILE="${CI_WS}/gitlab-runner-podman.log"


# Set a unique variable CONTAINER_NAME
CONTAINER_NAME="GitLabRunnerPodmanExec_BuildID${CUSTOM_ENV_CI_BUILD_ID}"
export CONTAINER_NAME

export SLURM_JOB_ID_FILE="${SLURM_IDS_PATH}/${CONTAINER_NAME}.txt"

# We need to create the temporary files in a directory with filesystem
# access on all nodes. Because we consider ${CONTAINER_NAME} to be unique,
# we use it as storage for this job.
export CONTAINER_WS="${CI_WS}/${CONTAINER_NAME}"

export CONTAINER_BUILDS_DIR="${CONTAINER_WS}/build"
#export CONTAINER_CACHE_DIR="${CONTAINER_WS}/cache"
export CONTAINER_SCRIPT_DIR="${CONTAINER_WS}/scripts"
export CONTAINER_STEPS_DIR="${CONTAINER_SCRIPT_DIR}/step_scripts"

# LOCAL prefix means it is from the view inside the container
export LOCAL_SCRIPT_DIR="/scripts"
export LOCAL_STEPS_DIR="${LOCAL_SCRIPT_DIR}/step_scripts"


# Create the proper mount options, so the build and cache directory are mounted properly
export PODMAN_MOUNT_OPTIONS=(
    "--mount=type=bind,src=${CONTAINER_BUILDS_DIR},dst=${CUSTOM_ENV_CI_BUILDS_DIR}"
    #"--mount=type=bind,src=${CONTAINER_CACHE_DIR},dst=${CUSTOM_ENV_CI_CACHE_DIR}"
    "--mount=type=bind,src=${CONTAINER_SCRIPT_DIR},dst=${LOCAL_SCRIPT_DIR}"
    )


# SLURM configuration variables.
#
# If the user sets any slurm variable or the variable USE_SLURM, this container
# will use slurm job submission
USE_SLURM=1 #${CUSTOM_ENV_USE_SLURM}
if [[ -z "${USE_SLURM}" || ${USE_SLURM} -ne 0 ]]; then
    SUPPORTED_SLURM_VARIABLES=(SLURM_PARTITION
                               SLURM_EXCLUSIVE
                               SLURM_TIME
                               SLURM_GRES
                               SLURM_ACCOUNT
                               SLURM_UPDATE_INTERVAL
                               SLURM_PENDING_LIMIT
                               SLURM_RUNNING_LIMIT
                               USE_SLURM)
    for slurm_var in ${SUPPORTED_SLURM_VARIABLES[*]}; do
        check_var="CUSTOM_ENV_${slurm_var}"
        if [[ -n "${!check_var}" ]]; then
          USE_SLURM=1
        fi
    done
fi
export USE_SLURM=1
# variables from slurm_utils we need to expose outside
export SLURM_UPDATE_INTERVAL
export SLURM_PENDING_LIMIT
export SLURM_RUNNING_LIMIT
export SLURM_GOOD_COMPLETED_STATUS
export SLURM_GOOD_PENDING_STATUS
export SLURM_BAD_STATUS


function ensure_executable_available() {
    local command=${1}

    if ! type -p "${command}" >/dev/null 2>/dev/null; then
        die "No ${command} executable found"
    fi
}
