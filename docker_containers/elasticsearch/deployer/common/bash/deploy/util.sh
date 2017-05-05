#!/bin/bash

# e.g. join , list of stuff => list,of,stuff
function join { local IFS="$1"; shift; echo "$*"; }
function os::int::deploy::join { local IFS="$1"; shift; echo "$*"; }

# turn foo=bar,baz=quux into nodeSelector: {"foo": "bar", "baz": "quux"}
function os::int::deploy::extract_nodeselector() {
  if [ -z "${1:-}" ]; then
    echo nodeSelector: "{}"
    return 0
  fi

  local inputstring="${1//\"/}"  # remove any errant double quotes in the inputs
  local selectors=()

  for keyvalstr in ${inputstring//\,/ }; do

    keyval=( ${keyvalstr//=/ } )

    if [[ -n "${keyval[0]}" && -n "${keyval[1]}" ]]; then
      selectors+=("\"${keyval[0]}\": \"${keyval[1]}\"")
    else
      echo "Could not make a node selector label from '${keyval[*]}'"
      exit 255
    fi
  done

  if [[ "${#selectors[*]}" -gt 0 ]]; then
    echo nodeSelector: "{" $(os::int::deploy::join , "${selectors[@]}") "}"
  fi
}

# try to get a route key/cert from the secret dir, or create from the hostname and CA in $dir.
# could end up without and fall back to router wildcard cert.
function os::int::deploy::procure_route_cert() {
  local dir="$1" secret_dir="$2" file="$3" hostnames="${4:-}"
  os::int::deploy::initialize_signing_conf "$dir" "$secret_dir"
  if [ -s $secret_dir/$file.crt ]; then
    # use files from secret if present
    cp {$secret_dir,$dir}/$file.key
    cp {$secret_dir,$dir}/$file.crt
  elif [ -n "${hostnames:-}" ]; then  #fallback to creating one
    openshift admin ca create-server-cert  \
      --key=$dir/$file.key \
      --cert=$dir/$file.crt \
      --hostnames=${hostnames} \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
  fi
}

# Create (or use from a secret dir) a CA and signing.conf to sign certs with.
declare -A signing_conf # only init once per directory
function os::int::deploy::initialize_signing_conf() {
  local dir="$1" secret_dir="$2"
  [ "${signing_conf[$dir]+set}" ] && return 0
  signing_conf["$dir"]=initialized

  # cp/generate CA
  if [ -s $secret_dir/ca.key ]; then
          cp {$secret_dir,$dir}/ca.key
          cp {$secret_dir,$dir}/ca.crt
          cp {$secret_dir,$dir}/ca.serial.txt || \
              (echo "01" > $dir/ca.serial.txt)
  else
      openshift admin ca create-signer-cert  \
        --key="${dir}/ca.key" \
        --cert="${dir}/ca.crt" \
        --serial="${dir}/ca.serial.txt" \
        --name="apiman-signer-$(date +%Y%m%d%H%M%S)"
  fi
  cat /dev/null > $dir/ca.db
  cat /dev/null > $dir/ca.crt.srl

  echo Generating signing configuration file
  cat - conf/signing.conf > $dir/signing.conf <<CONF
[ default ]
dir                     = ${dir}               # Top dir
CONF
}

# create a kubeconfig from token file when in a container.
# just make a copy of the user's kubeconfig when running directly.
function os::int::deploy::write_kubeconfig() {
  local scratch_dir="$1" project="$2" 
  # only needed for writing a kubeconfig:
  local token_file=${TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}

  # set up configuration for openshift client
  if [ -z "${CREATE_KUBECONFIG:-}" ]; then
    # in development scenario, use existing config, but make a copy so we can add to it
    cp ~/.kube/config "$scratch_dir/kubeconfig" \
      || cp "${KUBECONFIG}" "$scratch_dir/kubeconfig"
    export KUBECONFIG="$scratch_dir/kubeconfig"
  else
    # craft a kubeconfig using account token, usually at $KUBECONFIG location
    local master_url=${MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
    local master_ca=${MASTER_CA:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
    oc config set-cluster master \
        --api-version='v1' \
        --certificate-authority="${master_ca}" \
        --server="${master_url}"
    oc config set-credentials account \
        --token="$(cat ${token_file})"
    oc config set-context current \
        --cluster=master \
        --user=account \
        --namespace="${project}"
    oc config use-context current
  fi
}
