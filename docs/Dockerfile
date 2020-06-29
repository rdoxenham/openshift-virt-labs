FROM quay.io/openshifthomeroom/workshop-dashboard:5.0.0

ADD https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest-4.4/openshift-client-linux.tar.gz /opt/app-root/bin/

USER root

COPY . /tmp/src

RUN rm -rf /tmp/src/.git* && \
    chown -R 1001 /tmp/src && \
    chgrp -R 0 /tmp/src && \
    chmod -R g+w /tmp/src && \
    tar -zxvf /opt/app-root/bin/openshift-client-linux.tar.gz -C /opt/app-root/bin/ && \
    chmod a+x /opt/app-root/bin/oc

USER 1001

RUN /usr/libexec/s2i/assemble
