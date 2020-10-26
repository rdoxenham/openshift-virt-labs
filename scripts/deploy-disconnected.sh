#!/usr/bin/env bash

systemctl start named

export VERSION=$(oc version | awk '{print $3;}')
export RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}' | xargs)
export PULL_SECRET=~/pull-secret.json
export UPSTREAM_REPO="quay.io/openshift-release-dev/ocp-release:$VERSION-x86_64"
export LOCAL_HOSTNAME=$(hostname -f)
export LOCAL_REG="$LOCAL_HOSTNAME:5000"
export LOCAL_REPO="ocp4/openshift4"

# Build a catalogue of the images we need to pull for the specific version being deployed
oc adm release extract --registry-config "${PULL_SECRET}" --to /tmp/images ${RELEASE_IMAGE}

# Configure a local registry pod to store the images
yum -y install podman httpd httpd-tools
mkdir -p /opt/registry/{auth,certs,data}
openssl req -newkey rsa:4096 -nodes -sha256 -keyout /opt/registry/certs/domain.key -x509 -days 365 -out /opt/registry/certs/domain.crt -subj "/C=GB/ST=London/L=London/O=Red Hat/OU=Product/CN=$LOCAL_HOSTNAME"
cp /opt/registry/certs/domain.crt $(pwd)/domain.crt
cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
htpasswd -bBc /opt/registry/auth/htpasswd dummy dummy
podman create --name poc-registry --net host -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" -e "REGISTRY_HTTP_SECRET=ALongRandomSecretForRegistry" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key docker.io/library/registry:2
podman start poc-registry
podman ps

# Extend pre-configured pull secret with the registry secret
cat > ~/reg-secret.txt << EOF
"$LOCAL_HOSTNAME:5000": {
    "email": "dummy@redhat.com",
    "auth": "ZHVtbXk6ZHVtbXk="
}
EOF

cp $PULL_SECRET $PULL_SECRET.orig
cat $PULL_SECRET | jq ".auths += {`cat ~/reg-secret.txt`}" > $PULL_SECRET

cat $PULL_SECRET | tr -d '[:space:]' > tmp-secret
mv -f tmp-secret $PULL_SECRET

# Mirror all of the images to the local registry
oc adm release mirror -a $PULL_SECRET --from=$UPSTREAM_REPO --to-release-image=$LOCAL_REG/$LOCAL_REPO:$VERSION --to=$LOCAL_REG/$LOCAL_REPO

# Add the local mirror override to the install-config
echo \
"imageContentSources:
- mirrors:
  - ocp4-bastion.cnv.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ocp4-bastion.cnv.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev" >> /root/ocp-install/install-config.yaml

# Patch the updated pull-secret in the install-config with the local registry credentials
sed -i "s|pullSecret:.*|pullSecret: '$(cat ~/pull-secret.json)'|g" ~/ocp-install/install-config.yaml
