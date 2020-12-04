#!/bin/bash
set -ex
project=${PROJECT:-default}
mode=${MODE:-install}
dir=${SCRATCH_DIR:-_output}  # for writing files to bundle into secrets
# only needed for writing a kubeconfig:
master_url=${MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
master_ca=${MASTER_CA:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
token_file=${TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}
keytool=${KEYTOOL:-${JAVA_HOME}/bin/keytool}

mkdir -p $dir

# set up configuration for openshift client
if [ -n "${WRITE_KUBECONFIG}" ]; then
    # craft a kubeconfig, usually at $KUBECONFIG location
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

for file in scripts/*.sh; do source $file; done
case "${mode}" in
    install)
        install_es
        ;;
    uninstall)
        scaleDown || :
        delete_es
        ;;
    reinstall)
        scaleDown || :
        delete_es
        install_es
        ;;
    migrate)
        uuid_migrate
        ;;
    upgrade)
        upgrade_es
        ;;
    stop)
        scaleDown
        ;;
    start)
        scaleUp
        ;;
    *)
        echo "Invalid mode provided. One of ['install'|'uninstall'|'reinstall'|'migrate'|'upgrade'|'start'|'stop'] was expected";
        exit 1
        ;;
esac
