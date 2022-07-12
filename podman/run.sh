#!/usr/bin/bash
# https://docs.gitlab.com/runner/executors/custom.html#run


# shellcheck source=./include.sh
source "${BASH_SOURCE[0]%/*}/include.sh"


ensure_executable_available podman
ensure_executable_available mktemp
ensure_executable_available basename

ensure_executable_available sacct
ensure_executable_available scancel
ensure_executable_available sbatch
ensure_executable_available srun
ensure_executable_available squeue
ensure_executable_available wc
ensure_executable_available awk


# External args
# Last argument is always the step name. The one before last is the step script
# Note: This script does not forward any additional arguments that are specified
#       in the config.toml file!!!
before_last=$(($#-1))
STEP_NAME_ARG="${!#}"
STEP_SCRIPT_ARG="${!before_last}"

if [[ ! -d "${CONTAINER_STEPS_DIR}" ]]; then
    mkdir -p "${CONTAINER_STEPS_DIR}"
fi
NUM_SCRIPTS="$(find "${CONTAINER_STEPS_DIR}" -maxdepth 1 -type f | wc -l)"
STEP_SCRIPT="${CONTAINER_STEPS_DIR}/${NUM_SCRIPTS}"
touch "${STEP_SCRIPT}"

# Save the step script as an increasing integer number as the name
# (so we preserve the order)
cp "${STEP_SCRIPT_ARG}" "${STEP_SCRIPT}"

# Only store the gitlab scripts until we reach the main {build,step}_script
if [ ! -f "${SLURM_JOB_ID_FILE}" ] && [[ ! "${STEP_NAME_ARG}" =~ ^(build|step)_script$ ]]; then

    echo -e "Storing the script for step ${STEP_NAME_ARG} for bulk submission."
    exit

elif [[ "${STEP_NAME_ARG}" =~ ^(build|step)_script$ ]]; then

    # We finally reached the main script, prepare the SLURM job
    RUN_STEPS_SCRIPT="${CONTAINER_SCRIPT_DIR}/run_stages.sh"
    LOCAL_RUN_STEPS_SCRIPT="${LOCAL_SCRIPT_DIR}/run_stages.sh"
    JOB_SCRIPT="${CONTAINER_SCRIPT_DIR}/job_script.sh"
    JOB_LOG=$(mktemp -p "${CONTAINER_WS}")
    JOB_ERR=$(mktemp -p "${CONTAINER_WS}")
    SLURM_CONFIG=("--job-name=${CONTAINER_NAME}")
    SLURM_CONFIG+=("--output=${JOB_LOG}")
    SLURM_CONFIG+=("--error=${JOB_ERR}")
    SLURM_CONFIG+=("--chdir=${CONTAINER_WS}")
    if [[ -n "${CUSTOM_ENV_SLURM_PARTITION}" ]]; then
        SLURM_CONFIG+=("--partition=${CUSTOM_ENV_SLURM_PARTITION}")
    fi
    if [[ -n "${CUSTOM_ENV_SLURM_TIME}" ]]; then
        SLURM_CONFIG+=("--time=${CUSTOM_ENV_SLURM_TIME}")
    fi
    if [[ -n "${CUSTOM_ENV_SLURM_GRES}" ]]; then
        SLURM_CONFIG+=("--gres=${CUSTOM_ENV_SLURM_GRES}")
    fi
    if [[ -n "${CUSTOM_ENV_SLURM_ACCOUNT}" ]]; then
        SLURM_CONFIG+=("--account=${CUSTOM_ENV_SLURM_ACCOUNT}")
    fi

    # Log the configuration
    echo -e "SLURM configuration:"
    printf "\t%s\n" "${SLURM_CONFIG[@]}"
    echo -e "\n"
    echo -e "Podman mount configuration:"
    printf "\t%s\n" "${PODMAN_MOUNT_OPTIONS[@]}"
    echo -e "\n"


    # Launch the container through slurm
    # Here, we use the HereDoc syntax to write a multi-line file.
    # Note: We don't quote EOF, so we get parameter expansion and
    #       command substitution.
    # Also Note: We can't use indentation for the last EOF since it would not
    #            be detected otherwise
cat << EOF > "${RUN_STEPS_SCRIPT}"
#!/bin/bash

# Since we named the scripts as integers and since 'ls' outputs the names
# sorted, we preserve the execution order here.
for scriptnum in \$(ls -1v ${LOCAL_STEPS_DIR}); do
    /bin/bash ${LOCAL_STEPS_DIR}/\${scriptnum}
done
EOF
    chmod +x "${RUN_STEPS_SCRIPT}"

cat << EOF > "${JOB_SCRIPT}"
#!/bin/bash

srun podman run --rm "${PODMAN_MOUNT_OPTIONS[@]}" "${CUSTOM_ENV_CI_JOB_IMAGE}" "${LOCAL_RUN_STEPS_SCRIPT}"
EOF
    chmod +x "${JOB_SCRIPT}"


    # Submission
    # shellcheck disable=SC2206
    COMMAND=(sbatch --parsable ${SLURM_CONFIG[*]} "${JOB_SCRIPT}")
    JOB_ID=$("${COMMAND[@]}") || \
        die "Command: ${COMMAND[*]} failed with exit code ${?}" "${CONTAINER_WS}"
    echo -e "Job submitted and pending with ID: ${JOB_ID}."
    squeue -u "${USER}"

    # Store the JOB_ID so `cleanup.sh` can read it and cancel the job if running
    # (e.g., when pressing the cancel button on gitlab). We consider that the
    # CONTAINER_NAME is unique at a given time, so we don't use locking or a list
    # of ids.
    echo "${JOB_ID}" > "${SLURM_JOB_ID_FILE}"

    slurm_wait_for_status "${JOB_ID}" "${SLURM_PENDING_LIMIT}" \
        "${SLURM_GOOD_PENDING_STATUS}" || die "encountered an error while waiting" \
        "${CONTAINER_WS}" "${JOB_ID}" "${JOB_LOG}" "${JOB_ERR}"

    echo -e "Job ${JOB_ID} started execution."
    slurm_wait_for_status "${JOB_ID}" "${SLURM_RUNNING_LIMIT}" \
        "${SLURM_GOOD_COMPLETED_STATUS}" || die "encountered an error while waiting" \
        "${CONTAINER_WS}" "${JOB_ID}" "${JOB_LOG}" "${JOB_ERR}"

    test -f "${JOB_ERR}" && test "$(cat "${JOB_ERR}")"  != "" && \
        die "encountered an error during execution" "${CONTAINER_WS}" "${JOB_ID}" "${JOB_LOG}" "${JOB_ERR}"

    echo -e "Job ${JOB_ID} completed."
    slurm_print_output "${JOB_ID}" "Log" "${JOB_LOG}" /dev/stdout
    slurm_print_output "${JOB_ID}" "Errors" "${JOB_ERR}" /dev/stdout

    rm "${JOB_SCRIPT}"
    exit $(slurm_get_derived_error_code ${JOB_ID})

# Run all scripts after {build,step}_script on the login node
else

    LOCAL_STEP_SCRIPT="${LOCAL_SCRIPT_DIR}/$(basename -- ${STEP_SCRIPT})"
    podman run --rm "${PODMAN_MOUNT_OPTIONS[@]}" "${CUSTOM_ENV_CI_JOB_IMAGE}" /bin/bash "${LOCAL_STEP_SCRIPT}"

fi
