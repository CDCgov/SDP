FROM openshift/jenkins-slave-base-centos7

MAINTAINER Tim Taylor <ttaylor@mitre.org>

ENV RUBY_VERSION=2.3 \
    PATH=/opt/rh/rh-nodejs4/root/usr/bin:/opt/rh/rh-ruby23/root/usr/local/bin:/opt/rh/rh-ruby23/root/usr/bin:${HOME}/bin:$PATH \
    BASH_ENV=/usr/local/bin/scl_enable \
    ENV=/usr/local/bin/scl_enable \
    LD_LIBRARY_PATH=/opt/rh/rh-nodejs4/root/usr/lib64:/opt/rh/rh-ruby23/root/usr/local/lib64:/opt/rh/rh-ruby23/root/usr/lib64 \
    X_SCLS='rh-nodejs4 rh-ruby23 ' \
    PROMPT_COMMAND=". /usr/local/bin/scl_enable"

COPY contrib/bin/scl_enable /usr/local/bin/scl_enable

# Install Ruby
RUN INSTALL_PKGS="rh-ruby23 rh-ruby23-ruby-devel rh-ruby23-rubygem-rake rh-ruby23-rubygem-bundler rh-nodejs4 postgresql-devel make gcc fontconfig bzip2" && \
    yum-config-manager --enable centos-sclo-rh-testing && \
    yum install -y --enablerepo=centosplus --setopt=tsflags=nodocs $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all -y && \
    curl -L https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 | \
    tar -jx && \
    mv phantomjs*/bin/phantomjs /usr/local/bin && \
    rm -rf phantomjs-*

# Put in place a config file that will use the proxy server
COPY contrib/npmrc /opt/rh/rh-nodejs4/root/usr/etc/npmrc

RUN chown -R 1001:0 $HOME && \
    chmod -R g+rw $HOME

USER 1001
