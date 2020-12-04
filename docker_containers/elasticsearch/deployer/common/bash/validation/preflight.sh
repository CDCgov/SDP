#!/bin/bash

set -e

# determine whether DNS resolves the master successfully
function os::int::pre::check_master_accessible() {
  local master_ca="$1" master_url="$2" output
  if output=$(curl -sSI --stderr - --connect-timeout 2 --cacert "$master_ca" "$master_url"); then
    echo "ok"
    return 0
  fi
  local rc=$?
  echo "unable to access master url $master_url"
  case $rc in # if curl's message needs interpretation
  51)
	  echo "The master server cert was not valid for ${master_url}."
	  echo "You most likely need to regenerate the master server cert;"
	  echo "or you may need to address the master differently."
	  ;;
  60)
	  echo "The master CA cert did not validate the master."
	  echo "If you have multiple masters, confirm their certs have the same CA."
	  ;;
  esac
  echo "See the error from 'curl ${master_url}' below for details:"
  echo -e "$output"
  return 1
}

# determine whether cert (assumed to be from deployer secret) has specified names
function os::int::pre::cert_should_have_names() {
  local file="$1"; shift
  local names=( "$@" )
  local output name cn san missing

  if ! output=$(openssl x509 -in "$file" -noout -text 2>&1); then
    echo "Could not extract certificate from $file. The error was:"
    echo "$output"
    return 1
  fi
  if san=$(echo -e "$output" | grep -A 1 "Subject Alternative Name:"); then
    missing=false
    for name in "${names[@]}"; do
      [[ "$san" != *DNS:$name* ]] && missing=true
    done
    if [[ $missing = true ]]; then
      echo "The supplied $file certificate is required to contain the following name(s) in the Subject Alternative Name field:"
      echo $@
      echo "Instead the certificate has:"
      echo -e "$san"
      echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
      return 1
    fi
  elif [[ $# -gt 1 ]]; then
    echo "The supplied $file certificate is required to have a Subject Alternative Name field containing these names:"
    echo $@
    echo "The certificate does not have the Subject Alternative Name field."
    echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
    return 1
  else
    cn=$(echo -e "$output" | grep "Subject:")
    if [[ "$cn" != *CN=$1* ]]; then
      echo "The supplied $file certificate does not contain $1 in the Subject field and lacks a Subject Alternative Name field."
      echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
      return 1
    fi
  fi
  return 0
}

# check if service account exists and make a context for it named after the account name.
# assumes cluster created in kubeconfig by os::int::deploy::write_kubeconfig
# also assumes user has access to read SAs and secrets
function os::int::pre::check_service_account() {
  local project="$1" account="$2" output
  # there's no good way for oc to filter the list of secrets; and there are often several token secrets per SA.
  # following template prints all tokens for heapster; --sort-by will order them earliest to latest, we will use the last.
  local sa_token_secret_template="{{range .items}}{{if eq .type \"kubernetes.io/service-account-token\"}}{{if eq \"$account\" (index .metadata.annotations \"kubernetes.io/service-account.name\")}}{{println .data.token}}{{end}}{{end}}{{end}}"

  # check that the SA exists and we can get its token
  if ! os::int::util::check_exists serviceaccount/"$account" >& /dev/null; then
    echo "Expected '$account' service account to exist in '$project' project, but it does not."
    echo "Please ensure you created all the service accounts with:"
    echo '  $ oc new-app apiman-deployer-account-template'
    return 1
  fi
  if ! output=$(oc get secret --sort-by=metadata.resourceVersion --template="$sa_token_secret_template" 2>&1); then
    echo "Error getting $account service account token; is the master running and are credentials working? Error from oc get secrets follows:"
    echo -n "$output"
    return 1
  elif [[ -z "${output:-}" ]]; then
    echo "Could not find $account service account token in $project; does it exist?"
    return 1
  fi
  local token=$(echo -e "$output" | tail -1 | base64 -d)

  # set up a config context using the account and most recent token
  local context=$(oc config view -o jsonpath="{.current-context}")
  local cluster=$(oc config view -o jsonpath="{.contexts[?(@.name==\"$context\")].context.cluster}")
  oc config set-credentials "${account}-serviceaccount" \
    --token="$token" >& /dev/null
  oc config set-context "${account}-serviceaccount" \
    --cluster="${cluster}" \
    --user="${account}-serviceaccount" \
    --namespace="${project}" >& /dev/null
}
