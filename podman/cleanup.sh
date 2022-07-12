#!/usr/bin/bash
# https://docs.gitlab.com/runner/executors/custom.html#cleanup

# shellcheck source=./include.sh
source "${BASH_SOURCE[0]%/*}/include.sh"


# Take care of slurm cleanup if needed
if [ -f "${SLURM_JOB_ID_FILE}" ]; then
    ensure_executable_available scancel
    ensure_executable_available squeue

    USE_SLURM=1
    JOBID=$(cat "${SLURM_JOB_ID_FILE}")
    rm "${SLURM_JOB_ID_FILE}" # not needed anymore
    # If the job isn't finished yet, we still need to cancel it
    scancel --quiet "${JOBID}"
fi

# Somehow, the work dir is leftover, that can indicate a job cancellation.
if [ -d "${CONTAINER_WS}" ]; then
    rm -rf "${CONTAINER_WS}"
fi

# Delete container root filesystems if it isn't asked to be preserved or there
# was an error in one of the previous step.
{
    echo -e "==============================="
    echo -e "Job: ${CUSTOM_ENV_CI_JOB_ID}"
    echo -e "Job started at: ${CUSTOM_ENV_CI_JOB_STARTED_AT}"
    echo -e "Pipeline: ${CUSTOM_ENV_CI_PIPELINE_ID}"

    if [[ "${USE_SLURM}" == 1 ]]; then
        squeue -u "${USER}"
    fi
} >> "${LOGFILE}"
