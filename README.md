# Merge Control Github Action

A Github action to check whether a merge/PR is permitted to happen between branches based on user-supplied rules.

## How to Use
1. Create a new action to trigger on (typically) a pull request,
2. Within `jobs.<job_id>.steps` of the action workflow, add a `uses` statement similar to the following (see below for use of the `with` statement).
   ```yml
   - uses: konsentus/action.control-merge@master
     with:
       workflow: a b c master
       feature_pattern: feature/*
       hotfix_pattern: hotfix/*
   ```

## Using the `with` statement

The with statement is used for this action to provide a pattern to be used for feature and hotfix branches (the concepts of both branch types are based on the GitFlow workflow), along with a list of branches to be used as a control workflow to allow merges from one branch to another (for multi-stage release processes etc).

Wildcards as allowed by `grep` are permitted in the source branch values, such as `hotfix/*`.

## Merging rules

The general rules for merging between different branches is that:

- a `feature` may **ONLY** merge into other features or `workflow[0]`
- `workflow[n]` may **ONLY** merge into `workflow[n+1]`
- a `hotfix` may merge into **ANY** branch

### Additional merging restrictions

- a `feature` or `workflow` branch may **ONLY** merge into **UNBLOCKED** `workflow` branches
- a `workflow` branch is considered **BLOCKED** when the HEAD of the target branch is an ancestor of the branch beyond the target branch
  - e.g. for workflow "a b c", if the latest commit on "b" has not been merged into "c", then "b" is blocked and "a" cannot merge into it
- the last stage on the `workflow` **CANNOT** be blocked
