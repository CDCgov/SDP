#!/bin/bash

set -ex

proxy_args=""
if [ "x$http_proxy" != "x" ]; then
  proxy_host=${http_proxy#*://} # Strip off URI protocol
  proxy_host=${proxy_host%:*}   # Isolate just the hostname
  proxy_port=${http_proxy##*:}  # Strip off everything before the port
  proxy_port=${proxy_port%/*}   # Remove the trailing '/'

  # Build proxy args for es plugin command
  proxy_args="-DproxyHost=${proxy_host} -DproxyPort=${proxy_port}"
fi

mkdir -p ${HOME}
ln -s /usr/share/elasticsearch /usr/share/java/elasticsearch

#/usr/share/elasticsearch/bin/plugin $proxy_args install -b com.floragunn/search-guard-ssl/${SG_SSL_VER}
#/usr/share/elasticsearch/bin/plugin $proxy_args install -b com.floragunn/search-guard-2/${SG_VER}
/usr/share/elasticsearch/bin/plugin $proxy_args install io.fabric8/elasticsearch-cloud-kubernetes/${ES_CLOUD_K8S_VER}
/usr/share/elasticsearch/bin/plugin $proxy_args install io.fabric8.elasticsearch/openshift-elasticsearch-plugin/${OSE_ES_VER}

mkdir /elasticsearch
mkdir -p $ES_CONF
chmod -R og+w $ES_CONF
chmod -R og+w /usr/share/java/elasticsearch ${HOME} /elasticsearch
chmod -R o+rx /etc/elasticsearch
#chmod +x /usr/share/elasticsearch/plugins/search-guard-2/tools/sgadmin.sh

PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
cat > ${HOME}/sgconfig/sg_internal_users.yml << CONF
---
  $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1):
    hash: $PASSWD
CONF
