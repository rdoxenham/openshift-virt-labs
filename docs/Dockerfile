FROM quay.io/openshifthomeroom/workshop-dashboard:5.0.1

USER root

ADD https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.6/openshift-client-linux.tar.gz /opt/app-root/bin/
ADD https://github.com/kubevirt/kubevirt/releases/download/v0.36.0/virtctl-v0.36.0-linux-amd64 /opt/app-root/bin/virtctl

COPY . /tmp/src

RUN rm -rf /tmp/src/.git* && \
    chown -R 1001 /tmp/src && \
    chgrp -R 0 /tmp/src && \
    chmod -R g+w /tmp/src && \
    tar -zxvf /opt/app-root/bin/openshift-client-linux.tar.gz -C /opt/app-root/bin/ && \
    chmod a+x /opt/app-root/bin/oc && \
    chmod a+x /opt/app-root/bin/virtctl

#ENV TERMINAL_TAB=split

USER 1001

RUN /usr/libexec/s2i/assemble
