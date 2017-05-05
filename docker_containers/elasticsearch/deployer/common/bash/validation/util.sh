#!/bin/bash

# set up a config context using a service account token, named ${account_name}-context
function os::int::util::generate_SA_kube_context() {
  local project=$1 account_name=$2
  # there's no good way for oc to filter the list of secrets; and there can be several token secrets per SA.
  # following template prints all tokens for heapster; --sort-by will order them earliest to latest, we will use the last.
  local output sa_token_secret_template="{{range .items}}{{if eq .type \"kubernetes.io/service-account-token\"}}{{if eq \"$account_name\" (index .metadata.annotations \"kubernetes.io/service-account.name\")}}{{println .data.token}}{{end}}{{end}}{{end}}"
  # check that the SA exists and we can get its token
  if ! output=$(oc get secret --sort-by=metadata.resourceVersion --template="$sa_token_secret_template" 2>&1); then
    echo "Error getting $account_name service account token; is the master running and are credentials working? Error from oc get secrets follows:"
    echo -n "$output"
    return 1
  elif [[ -z "${output:-}" ]]; then
    echo "Could not find $account_name service account token in $project; does it exist?"
    return 1
  fi
  local token=$(echo -e "$output" | tail -1 | base64 -d)
  # set up a config context using the account's most recent token
  oc config set-credentials ${account_name}-serviceaccount \
    --token="$token" >& /dev/null
  oc config set-context ${account_name}-context \
    --cluster=deployer-master \
    --user=${account_name}-serviceaccount \
    --namespace="$project" >& /dev/null
}

# invoke oc get with given parameters and fail with error output if nothing comes back.
function os::int::util::check_exists() {
  local output object="$1"; shift
  if ! output=$(oc get "$object" "$@" 2>&1); then
    echo "Error running oc get $object:"
    echo -e "$output"
    echo "The $object API object must exist for a valid deployment."
    return 1
  elif [ -z "${output:-}" ]; then
    echo "oc get $object did not return any of the expected objects."
    echo "The correct $object API object(s) must exist for a valid deployment."
    return 1
  fi
  echo -e "$output"
  return 0
}

# take a list of objects and test all of them. if any are missing, fail at the end.
function os::int::util::check_each_exists() {
  local object missing=false
  for object in "$@"; do
    if ! output=$(check_exists "$object"); then
      missing=true
      echo -e "$output"
    fi
  done
  [ "$missing" = true ] && return 1
  return 0
}

# when each test is a precondition for the next to have much meaning;
# abort the first time something fails. else print "ok".
function os::int::util::check_chained_validations() {
  local func rc=0 output
  for func in "$@"; do
    output=$($func) || {
      rc=$?
      echo -e "$output"
      break # each test is a precondition for the next to have much meaning
    }
  done
  [ "$rc" -eq 0 ] && echo "ok"
  return $rc
}

# run a series of tests listed in the parameters.
# they should return 0 (success), 1 (failure), or 2 (retry).
# handle output and logic. first failure ends the validation.
function os::int::util::validate() {
  echo =========================
  echo BEGINNING VALIDATION
  local success=() failure=false output func rc
  for func in "$@"; do
    while echo "--- $func ---"; do
      if output="$($func 2>&1)"; then
        success+=("$func: $output")
        break
      else
        rc=$?
        case $rc in
          1) # invalid
            echo ======== ERROR =========
            echo "$func: "
            echo -e "$output"
            echo ========================
            failure=true
            break
            ;;
          2) # retry
            echo ======== RETRY =========
            echo "$func: "
            echo -e "$output"
            echo "Will retry in 5 seconds."
            sleep 5
            echo ========================
            ;;
          *)
            echo ======== ERROR =========
            echo "$func: "
            echo -e "$output"'\n'"unexpected return code: $rc"
            echo ========================
            failure=true
            break
            ;;
        esac
      fi
    done
  done

  echo
  if [[ $failure = true ]]; then
    echo "VALIDATION FAILED"
    echo ========================
    return 255
  fi

  echo "VALIDATION SUCCEEDED"
  echo ========================
  for win in "${success[@]}"; do echo $win; done
}
