FROM centos:centos7

MAINTAINER Ben Parees <bparees@redhat.com>

ENV HOME=/home/jenkins \
    http_proxy=http://gatekeeper.mitre.org:80/ \
    https_proxy=http://gatekeeper.mitre.org:80/ \
    no_proxy=172.30.0.1,172.30.111.77,172.30.253.251,.local

USER root

# Add MITRE CA certificates to system trusted store
COPY certs/*.pem /etc/pki/ca-trust/source/anchors/
RUN /usr/bin/update-ca-trust extract

# Install headless Java
RUN yum install -y centos-release-scl-rh && \
    INSTALL_PKGS="bc gettext git java-1.8.0-openjdk-headless lsof nss_wrapper rsync tar unzip which zip" && \
    yum install -y --setopt=tsflags=nodocs install $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all && \
    mkdir -p /home/jenkins && \
    chown -R 1001:0 /home/jenkins && \
    chmod -R g+w /home/jenkins && \
    curl -L https://github.com/openshift/origin/releases/download/v1.3.0/openshift-origin-client-tools-v1.3.0-3ab7af3d097b57f933eccef684a714f2368804e7-linux-64bit.tar.gz | \
    tar -zx && \
    mv openshift*/oc /usr/local/bin && \
    rm -rf openshift-origin-client-tools-*

# Copy a remoting jar that honors the no_proxy env variable
COPY contrib/lib/remoting-2.60.jar /home/jenkins/remoting.jar

# Copy the entrypoint
ADD contrib/bin/* /usr/local/bin/

# Run the Jenkins JNLP client
ENTRYPOINT ["/usr/local/bin/run-jnlp-client"]
