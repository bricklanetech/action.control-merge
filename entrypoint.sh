#!/bin/bash -l

if [ -z "${GITHUB_HEAD_REF}" ] || [ -z "${GITHUB_BASE_REF}" ]; then
    # expected env vars dont exist, cannot continue
    echo "::set-output name=response::✘ Either GITHUB_HEAD_REF or GITHUB_BASE_REF are not defined. Cannot continue"
    exit 2
fi

# get position of value ($1) within an array ($2)
# return -1 if not found
indexOf() {
    local VALUE="${1}"
    shift
    local ARRAY=($@)
    local POSITION=-1

    for i in "${!ARRAY[@]}"; do
        if [[ "${ARRAY[$i]}" = "${VALUE}" ]]; then
            POSITION=${i}
            break
        fi
    done

    echo ${POSITION}
}

# checks if source branch is a hotfix and returns success (or failure if not)
isHotfix() {
    return $(echo "${SOURCE_BRANCH}" | grep -qe "${HOTFIX_PATTERN}")
}

# checks if source branch is a feature and returns success (or failure if not)
isFeature() {
    TARGET=${1:-$SOURCE_BRANCH}
    return $(echo "${TARGET}" | grep -qe "${FEATURE_PATTERN}")
}

# checks if merge is permitted via the defined workflow array
# workflow array defined that item[n] can only be merged into item[n+1]
isMergeAllowedInWorkflow() {
    # features only allowed to merge into start of workflow (n=0)
    if isFeature; then
        if [ "${POSITION_TARGET}" -eq "0" ] || isFeature $TARGET_BRANCH; then
            echo "--> source is feature branch and target either another feature or start of workflow"
            return 0
        fi
        echo "--> source is feature, but target is not valid"
        return 1
    fi

    # if not coming from hotfix or feature, both source and target MUST be defined in workflow branches
    if [[ "${POSITION_SOURCE}" -eq "-1" || "${POSITION_TARGET}" -eq "-1" ]]; then
        echo "--> either source or target branch is unknown"
        return 1
    fi

    # workflow merged only permitted from immediately below steps
    if [ "${POSITION_TARGET}" -eq "$((POSITION_SOURCE + 1))" ]; then
        return 0
    fi

    echo "--> Merge not allowed"
    return 1
}

isBranchBlocked() {
    FINAL_WORKFLOW_BRANCH=${WORKFLOW[-1]}
    AFTER_TARGET_BRANCH=${WORKFLOW[$((POSITION_TARGET + 1))]}

    # The last branch in the workflow cannot be blocked (since there is no other step)
    if [ "${TARGET_BRANCH}" = "${FINAL_WORKFLOW_BRANCH}" ]; then
        echo "--> last step in the workflow. Not blockable"
        return 0
    fi

    # target branch is considered blocked if its current HEAD is ahead of the next branch HEAD
    # ie the head of the 'target' branch is not an ancester of the 'after target' branch
    if git merge-base --is-ancestor \
        $(git rev-parse origin/${TARGET_BRANCH}) \
        $(git rev-parse origin/${AFTER_TARGET_BRANCH})
    then
        echo "--> target branch is not blocked"
        return 0
    fi

    echo "--> Branch is blocked"

    TARGET_BRANCH_LAST_COMMIT_HASH=$(git rev-parse origin/${TARGET_BRANCH})
    COMMITTER=$(git show -s --format='%an' ${TARGET_BRANCH_LAST_COMMIT_HASH})

    echo "✘ Branch ${TARGET_BRANCH} is awaiting merge into ${AFTER_TARGET_BRANCH}, please check with ${COMMITTER}"
    return 1
}

SOURCE_BRANCH=${GITHUB_HEAD_REF}
TARGET_BRANCH=${GITHUB_BASE_REF}
WORKFLOW=(${INPUT_WORKFLOW})
HOTFIX_PATTERN=${INPUT_HOTFIX_PATTERN}
FEATURE_PATTERN=${INPUT_FEATURE_PATTERN}

POSITION_SOURCE=$(indexOf ${SOURCE_BRANCH} "${WORKFLOW[@]}")
POSITION_TARGET=$(indexOf ${TARGET_BRANCH} "${WORKFLOW[@]}")

# mark repo directory as safe to prevent 'dubious ownership' detected in the repository
git config --global --add safe.directory /github/workspace

# hotfixes can be merged anywhere
echo "-> checking if hotfix"
if isHotfix; then
    echo "::set-output name=response::✔ ${SOURCE_BRANCH} is a hotfix branch"
    exit 0
fi

echo "-> checking if merge is allowed in the workflow rules"
if ! isMergeAllowedInWorkflow; then
    echo "::set-output name=response::✘ Workflow does not allow ${SOURCE_BRANCH} to be merged into ${TARGET_BRANCH}"
    exit 1
fi

echo "-> checking if branch is blocked"
if ! isBranchBlocked; then
    echo "::set-output name=response::✘ ${TARGET_BRANCH} is currently blocked"
    exit 1
fi

echo "::set-output name=response::✔ ${SOURCE_BRANCH} is allowed to merge into ${TARGET_BRANCH}"
