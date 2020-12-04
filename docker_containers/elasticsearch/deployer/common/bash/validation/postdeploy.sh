#!/bin/bash

# test that specified PVCs exist and are bound; if not, retry briefly before failing.
function os::int::post::check_attached_pvcs() {
  # function parameters can specify PVC names or label selector
  local template='{{range .items}}{{println .metadata.name " " .status.phase}}{{end}}'
  # check that the PVCs exist and are bound
  local i line output unbound=()
  for i in 1 2 3 4 5; do
    if ! output=$(os::int::util::check_exists persistentvolumeclaim --template="$template" "$@"); then
      echo -e "$output"
      echo "The deployment requires a PVC for each storage pod and will not run."
      return 1
    fi
    unbound=()
    while IFS= read -r line; do
      line=( ${line:-} ) # name, phase for each pvc
      [ "${#line[@]}" -eq 0 ] && continue
      [ "${line[1]}" != Bound ] && unbound+=( "${line[0]}" )
    done <<< "$output"
    [ "${#unbound[*]}" -eq 0 ] && break
    sleep 1
  done
  if [ "${#unbound[*]}" -ne 0 ]; then
    echo "The following required PVCs have not been bound to a PhysicalVolume:"
    echo "  ${unbound[@]}"
    echo "The corresponding storage pod instances will not run without a bound PVC."
    echo "Please create satisfying PhysicalVolumes to enable this deployment."
    return 1
  fi
  return 0
}


# test the expected RCs exist and have the right number of replicas.
function os::int::post::check_deployed_rcs() {
  local selector=$1; shift  # e.g. infra=metrics - select all RCs of interest
  local func_name=$1; shift # function to validate each RC; should take two args, RC name and count, write and fail if count is wrong
  local -a expected_rcs=( "$@" )
  # get all RCs and replica count
  local template='{{range .items}}{{println .metadata.name " " .spec.replicas}}{{end}}'
  local i line output repc rc_broken 
  if ! output=$(os::int::util::check_exists replicationcontroller --template="$template" --selector="$selector"); then
    echo -e "$output"
    echo "The deployed replication controllers are missing. Please re-deploy."
    return 1
  fi
  # read the RCs found into a hash of name => #replicas
  local -A found_rcs=()
  while IFS=$'\n' read -r line; do
    line=( ${line:-} ) # name, replicas for each RC
    [ "${#line[@]}" -eq 0 ] && continue
    found_rcs["${line[0]}"]="${line[1]}"
  done <<< "$output"
  # compare to what we expect to see.
  for repc in ${expected_rcs[@]}; do
    if ! test "${found_rcs[$repc]+set}"; then
      rc_broken=true
      echo "ReplicationController $repc should exist but does not. Please re-deploy."
      continue
    fi
    $func_name "$repc" "${found_rcs[$repc]}" || rc_broken=true
  done
  # TODO: test whether only expected_rcs were found
  [ "${rc_broken:-}" ] && return 1
  return 0
}

# Test the related pods exist and are running. If they're not running and ready,
# look at events to see if we can figure out why.
function os::int::post::check_deployed_pods() {
  local selector=$1; shift  # e.g. infra=metrics - select all pods of interest
  local -a rcs=( "$@" )     # only check pods from these ReplicationControllers
  local events_output pods_output line repc
  # first get all related pods
  local pods_template='{{range .items}}{{print .metadata.name " " .metadata.labels.name " " .status.phase}}{{range .status.conditions}}{{if eq .type "Ready"}} {{.status}}{{end}}{{end}}{{println}}{{end}}'
  local -A expected_rcs=()
  for repc in "${expected_rcs[@]}"; do expected_rcs["$repc"]=1; done
  if ! pods_output=$(os::int::util::check_exists pod --selector="$selector" --template="$pods_template"); then
    echo -e "$pods_output"
    echo "The expected deployment pods are missing. Please re-deploy." # this would be weird
    return 1
  fi
  # now we get available events so that we can refer to them when looking at pods.
  # there is no way to scope our oc get to just events we care about, so get them all.
  # the template only prints out events that are related to a pod.
  local events_template='{{range .items}}{{if and (eq .involvedObject.kind "Pod") (or (eq .reason "Failed") (eq .reason "FailedScheduling")) }}{{.involvedObject.name}} {{.reason}} {{.metadata.name}}
{{end}}{{end}}
'
  if ! events_output=$(oc get events --sort-by=.metadata.resourceVersion --template="$events_template"); then
    echo "Error while getting project events:"
    echo -e "$pods_output"
    return 1
  fi
  local -A failed_event=() failed_schedule=()
  while IFS=$'\n' read -r line; do
    line=( ${line:-} ) # pod, reason, event name for each event
    [ "${#line[@]}" -eq 0 ] && continue
    local pod_name="${line[0]}"
    local reason="${line[1]}"
    local event_name="${line[2]}"
    [ "$reason" = Failed ] && failed_event["$pod_name"]="$event_name"
    [ "$reason" = FailedScheduling ] && failed_schedule["$pod_name"]="$event_name"
  done <<< "$events_output"
  #
  # now process the pods with events as background
  local pending=false broken=false
  while IFS=$'\n' read -r line; do # <<< "$pods_output"
    line=( ${line:-} ) # name, label, phase for each pod
    [ "${#line[@]}" -eq 0 ] && continue
    local name="${line[0]}"
    local label="${line[1]}"
    local phase="${line[2]}"
    local ready="${line[3]}"
    test "${expected_rcs[$label]+set}" || continue # not from a known rc
    case "$phase" in
      Running)
        [ "$ready" = True ] && continue # doing fine; else:
        echo "Pod $name from ReplicationController $label is running but not marked ready."
        echo "This is most often due to either startup latency or crashing for lack of other services."
        echo "It should resolve over time; if not, check the pod logs to see what is going wrong."
        echo "  * * * * "
        pending=true
        ;;
      Pending)
        # find out why it's pending
        if test "${failed_schedule[$name]+set}"; then
          broken=true
          echo "ERROR: Pod $name from ReplicationController $label could not be scheduled (placed on a node)."
          echo "This is most often due to a faulty nodeSelector or lack of node availability."
          echo "There was an event for this pod with the following message:"
          oc get event/"${failed_schedule[$name]}" --template='{{println .message}}' 2>&1
          echo "  * * * * "
        elif test "${failed_event[$name]+set}"; then
          broken=true
          echo "Pod $name from ReplicationController $label specified an image that cannot be pulled."
          echo "ERROR: This is most often due to the image name being wrong or the docker registry being unavailable."
          echo "Ensure that you used the correct IMAGE_PREFIX and IMAGE_VERSION with the deployment."
          echo "There was an event for this pod with the following message:"
          oc get event/"${failed_event[$name]}" --template='{{println .message}}' 2>&1
          echo "  * * * * "
        else
          echo "Pod $name from ReplicationController $label is in a Pending state."
          echo "This is most often due to waiting for the container image to pull and should eventually resolve."
          echo "  * * * * "
          pending=true
        fi
        ;;
      *)
        broken=true
        echo "ERROR: Pod $name from ReplicationController $label is in a $phase state, which is not normal."
        ;;
    esac
  done <<< "$pods_output"
  [ "$broken" = true ] && return 1
  [ "$pending" = true ] && return 2
  return 0
}

# test the route exists and is properly configured
function os::int::post::test_deployed_route() {
  local route="$1"
  # note: template cycles through all ingress statuses looking for any that are admitted. one active ingress is enough.
  local rc=0 output template='{{.spec.host}} {{.spec.tls.termination}} {{range .status.ingress}}{{range .conditions}}{{if and (eq .type "Admitted") (eq .status "True")}}True {{end}}{{end}}{{end}}'
  if ! output=$(os::int::util::check_exists route "$route" --template="$template"); then
    echo -e "$output"
    echo "The $route route is missing or broken. Please re-deploy."
    return 1
  fi
  output=($output) # hostname, tls termination type, admission condition
  local name="${output[0]}"
  local tls="${output[1]}"
  local admitted="${output[2]:-False}"
  # if the route doesn't have the right condition, complain
  if [ "$admitted" != True ]; then
    echo "The $route route is not active."
    echo "This often means that the route has already been created (likely in another project) and this one is newer."
    echo "It can also mean that no router has been deployed."
    oc get route "$route" --template='{{range .status.ingress}}{{range .conditions}}{{println .reason ":" .message}}{{end}}{{end}}' 2>&1
    rc=1
  fi
  case "$tls" in
    passthrough) # nothing to check
      ;;
    reencrypt)
      test_reencrypt_route "$name" || rc=1
      ;;
    *)
      echo "Invalid TLS termination type for $route route: $tls"
      echo "You may need to re-create the route or redeploy."
      rc=1
      ;;
  esac
  return $rc
}

