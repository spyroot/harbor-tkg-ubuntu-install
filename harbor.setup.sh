exit_on_error() {
    exit_code=$1
    last_command=${@:2}
    if [ $exit_code -ne 0 ]; then
        >&2 echo "\"${last_command}\" command failed with exit code ${exit_code}."
        exit $exit_code
    fi
  }

HARBOR_BASE=/root/harbor
HARBOR_CERT=/data/cert
DOCKER_CERT=/etc/docker/cert.d
HARBOR_PASS="VMware1!"

LOCAL=harbor.vmwarelab.edu
USER=tkg
HOST=$(echo ${LOCAL} | cut -d"." -f1)
CWD="$(pwd)"

HARBOR_BASE=$(echo ${HARBOR_BASE} | sed 's:/*$::')
HARBOR_CERT=$(echo ${HARBOR_CERT} | sed 's:/*$::')
DOCKER_CERT=$(echo ${DOCCKER_CERT} | sed 's:/*$::')

[[ -z "$LOCAL" ]] && { echo "Error: registry name empty"; exit 1; }

if [ -d "$HARBOR_BASE" ]; then
      echo "Installing config files in ${HARBOR_BASE}..."
else
      echo "Error: ${HARBOR_BASE} not found. Can not continue."
      exit 1
fi

if [ ! -f ${HARBOR_BASE}/harbor.yml.tmpl ]; then
   echo "Harbor dir has not template ${HARBOR_BASE}/harbor.yml"; exit 2;
fi

DOCKER_COMPOSER_GIT_VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)
DOCKER_COMPOSER_LOCAL_VER=$(/usr/local/bin/docker-compose --version)
DESTINATION=/usr/local/bin/docker-compose

if [[ $DOCKER_COMPOSER_LOCAL_VER != *"${DOCKER_COMPOSER_GIT_VERSION}"* ]]; then
  sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION
  sudo chmod 755 $DESTINATION
fi


cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${LOCAL}
DNS.2=${HOST}
EOF

# ca
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -sha512 -days 3650 \
 -subj "/C=US/ST=PaloAlto/L=PaloAlto/O=VMware/OU=Personal/CN=${LOCAL}" \
 -key ca.key \
 -out ca.crt

#server
openssl genrsa -out ${LOCAL}.key 4096
if [ ! -f ${LOCAL}.key ]; then
  echo "failed generate ca key ${LOCAL}.key check openssl tool"; exit 2;
fi

openssl req -sha512 -new \
    -subj "/C=US/ST=PaloAlto/L=PaloAlto/O=VMware/OU=Personal/CN=${LOCAL}" \
    -key ${LOCAL}.key \
    -out ${LOCAL}.csr 2>/dev/null

if [ ! -f ${LOCAL}.csr ]; then
  echo "failed create ${LOCAL}.csr"; exit 2;
fi

openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in ${LOCAL}.csr \
    -out ${LOCAL}.crt 2>/dev/null

if [ ! -f ${LOCAL}.crt ]; then
  echo "failed create ${LOCAL}.crt"; exit 2;
fi


### copy cert for harbor
if [[ -d $HARBOR_CERT ]]; then
       echo "Regenerating certs";
       rm -rf $HARBOR_CERT;
       mkdir -p $HARBOR_CERT;
else
       echo "Creating ${HABOR_CERT}";
       mkdir -p $HARBOR_CERT;
fi

cp ${LOCAL}.crt $HARBOR_CERT/
cp ${LOCAL}.key $HARBOR_CERT/

CRT_PATH=${HARBOR_CERT}/${LOCAL}.crt
KEY_PATH=${HARBOR_CERT}/${LOCAL}.key
if [ ! -f $CRT_PATH ]; then
  echo "failed copy ${CRT_PATH}"; exit 2;
fi

if [ ! -f $KEY_PATH ]; then
  echo "failed copy $KEY_PATH"; exit 2;
fi

openssl x509 -inform PEM -in ${LOCAL}.crt -out ${LOCAL}.cert
DOCKER_CERT_DIR=${DOCKER_CERT}/${LOCAL}

if [[ -d $DOCKER_CERT_DIR ]]; then
     echo "Regenerating docker registry certs";
     rm -rf $DOCKER_CERT_DIR;
fi

DOCKER_KEY_FILE=$DOCKER_CERT_DIR/${LOCAL}.key
DOCKER_CERT_FILE=$DOCKER_CERT_DIR/${LOCAL}.cert

mkdir -p $DOCKER_CERT_DIR
cp ${LOCAL}.key $DOCKER_CERT_DIR/
cp ${LOCAL}.cert $DOCKER_CERT_DIR/ 
cp ca.crt $DOCKER_CERT_DIR/

service docker restart
DOCKER_RUNNING=$(systemctl is-active --quiet service)
[[ ! -z "$DOCKER_RUNNING" ]] && { echo "Error: failed restart docker."; exit 1; }

echo "Installing Harbor";
${HARBOR_BASE}/.harbor.yml.tmpl $HARBOR_BASE/harbor.yml
sed -i '/certificate/s/${DOCKER_CERT_FILE}/}/g' HARBOR_BASE/harbor.yml 
sed -i '/private_key/s/${DOCKER_KEY_FILE}/g' HARBOR_BASE/harbor.yml
sed -i '/harbor_admin_password/s/${HARBOR_PASS}/g' HARBOR_BASE/harbor.yml

$HARBOR_BASE/install.sh

xargs -n1 docker pull << EOF
registry.tkg.vmware.run/kind/node:v1.18.2_vmware.1
registry.tkg.vmware.run/calico-all/cni-plugin:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/kube-controllers:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/node:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/pod2daemon:v3.11.2_vmware.1
registry.tkg.vmware.run/ccm/manager:v1.1.0_vmware.2
registry.tkg.vmware.run/cluster-api/cluster-api-aws-controller:v0.5.3_vmware.1
registry.tkg.vmware.run/cluster-api/cluster-api-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/cluster-api/cluster-api-vsphere-controller:v0.6.4_vmware.1
registry.tkg.vmware.run/cluster-api/kube-rbac-proxy:v0.4.1_vmware.2
registry.tkg.vmware.run/cluster-api/kubeadm-bootstrap-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/cluster-api/kubeadm-control-plane-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/csi/csi-attacher:v1.1.1_vmware.7
registry.tkg.vmware.run/csi/csi-livenessprobe:v1.1.0_vmware.7
registry.tkg.vmware.run/csi/csi-node-driver-registrar:v1.1.0_vmware.7
registry.tkg.vmware.run/csi/csi-provisioner:v1.4.0_vmware.2
registry.tkg.vmware.run/csi/volume-metadata-syncer:v1.0.2_vmware.1
registry.tkg.vmware.run/csi/vsphere-block-csi-driver:v1.0.2_vmware.1
registry.tkg.vmware.run/cert-manager/cert-manager-controller:v0.11.0_vmware.1
registry.tkg.vmware.run/cert-manager/cert-manager-cainjector:v0.11.0_vmware.1
registry.tkg.vmware.run/cert-manager/cert-manager-webhook:v0.11.0_vmware.1
registry.tkg.vmware.run/coredns:v1.6.7_vmware.1
registry.tkg.vmware.run/etcd:v3.4.3_vmware.5
registry.tkg.vmware.run/kube-apiserver:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-controller-manager:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-proxy:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-scheduler:v1.18.2_vmware.1
registry.tkg.vmware.run/pause:3.2
EOF

docker -u ${USER} login ${LOCAL}

xargs -n2 docker tag << EOF
registry.tkg.vmware.run/kind/node:v1.18.2_vmware.1 ${LOCAL}/library/kind/node:v1.18.2_vmware.1
registry.tkg.vmware.run/calico-all/cni-plugin:v3.11.2_vmware.1 ${LOCAL}/library/calico-all/cni-plugin:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/kube-controllers:v3.11.2_vmware.1 ${LOCAL}/library/calico-all/kube-controllers:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/node:v3.11.2_vmware.1 ${LOCAL}/library/calico-all/node:v3.11.2_vmware.1
registry.tkg.vmware.run/calico-all/pod2daemon:v3.11.2_vmware.1 ${LOCAL}/library/calico-all/pod2daemon:v3.11.2_vmware.1
registry.tkg.vmware.run/ccm/manager:v1.1.0_vmware.2 ${LOCAL}/library/ccm/manager:v1.1.0_vmware.2
registry.tkg.vmware.run/cluster-api/cluster-api-aws-controller:v0.5.3_vmware.1 ${LOCAL}/library/cluster-api/cluster-api-aws-controller:v0.5.3_vmware.1
registry.tkg.vmware.run/cluster-api/cluster-api-controller:v0.3.5_vmware.1 ${LOCAL}/library/cluster-api/cluster-api-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/cluster-api/cluster-api-vsphere-controller:v0.6.4_vmware.1 ${LOCAL}/library/cluster-api/cluster-api-vsphere-controller:v0.6.4_vmware.1
registry.tkg.vmware.run/cluster-api/kube-rbac-proxy:v0.4.1_vmware.2 ${LOCAL}/library/cluster-api/kube-rbac-proxy:v0.4.1_vmware.2
registry.tkg.vmware.run/cluster-api/kubeadm-bootstrap-controller:v0.3.5_vmware.1 ${LOCAL}/library/cluster-api/kubeadm-bootstrap-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/cluster-api/kubeadm-control-plane-controller:v0.3.5_vmware.1 ${LOCAL}/library/cluster-api/kubeadm-control-plane-controller:v0.3.5_vmware.1
registry.tkg.vmware.run/csi/csi-attacher:v1.1.1_vmware.7 ${LOCAL}/library/csi/csi-attacher:v1.1.1_vmware.7
registry.tkg.vmware.run/csi/csi-livenessprobe:v1.1.0_vmware.7 ${LOCAL}/library/csi/csi-livenessprobe:v1.1.0_vmware.7
registry.tkg.vmware.run/csi/csi-node-driver-registrar:v1.1.0_vmware.7 ${LOCAL}/library/csi/csi-node-driver-registrar:v1.1.0_vmware.7
registry.tkg.vmware.run/csi/csi-provisioner:v1.4.0_vmware.2 ${LOCAL}/library/csi/csi-provisioner:v1.4.0_vmware.2
registry.tkg.vmware.run/csi/volume-metadata-syncer:v1.0.2_vmware.1 ${LOCAL}/library/csi/volume-metadata-syncer:v1.0.2_vmware.1
registry.tkg.vmware.run/csi/vsphere-block-csi-driver:v1.0.2_vmware.1 ${LOCAL}/library/csi/vsphere-block-csi-driver:v1.0.2_vmware.1
registry.tkg.vmware.run/cert-manager/cert-manager-controller:v0.11.0_vmware.1 ${LOCAL}/library/cert-manager/cert-manager-controller:v0.11.0_vmware.1
registry.tkg.vmware.run/cert-manager/cert-manager-cainjector:v0.11.0_vmware.1 ${LOCAL}/library/cert-manager/cert-manager-cainjector:v0.11.0_vmware.1 
registry.tkg.vmware.run/cert-manager/cert-manager-webhook:v0.11.0_vmware.1 ${LOCAL}/library/cert-manager/cert-manager-webhook:v0.11.0_vmware.1
registry.tkg.vmware.run/coredns:v1.6.7_vmware.1 ${LOCAL}/library/coredns:v1.6.7_vmware.1
registry.tkg.vmware.run/etcd:v3.4.3_vmware.5 ${LOCAL}/library/etcd:v3.4.3_vmware.5
registry.tkg.vmware.run/kube-apiserver:v1.18.2_vmware.1 ${LOCAL}/library/kube-apiserver:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-controller-manager:v1.18.2_vmware.1 ${LOCAL}/library/kube-controller-manager:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-proxy:v1.18.2_vmware.1 ${LOCAL}/library/kube-proxy:v1.18.2_vmware.1
registry.tkg.vmware.run/kube-scheduler:v1.18.2_vmware.1 ${LOCAL}/library/kube-scheduler:v1.18.2_vmware.1
registry.tkg.vmware.run/pause:3.2 ${LOCAL}/library/pause:3.2    
EOF

xargs -n1 docker push << EOF
${LOCAL}/library/ind/node:v1.18.2_vmware.1
${LOCAL}/library/calico-all/cni-plugin:v3.11.2_vmware.1
${LOCAL}/library/calico-all/kube-controllers:v3.11.2_vmware.1
${LOCAL}/library/calico-all/node:v3.11.2_vmware.1
${LOCAL}/library/calico-all/pod2daemon:v3.11.2_vmware.1
${LOCAL}/library/ccm/manager:v1.1.0_vmware.2
${LOCAL}/library/cluster-api/cluster-api-aws-controller:v0.5.3_vmware.1
${LOCAL}/library/cluster-api/cluster-api-controller:v0.3.5_vmware.1
${LOCAL}/library/cluster-api/cluster-api-vsphere-controller:v0.6.4_vmware.1
${LOCAL}/library/cluster-api/kube-rbac-proxy:v0.4.1_vmware.2
${LOCAL}/library/cluster-api/kubeadm-bootstrap-controller:v0.3.5_vmware.1
${LOCAL}/library/cluster-api/kubeadm-control-plane-controller:v0.3.5_vmware.1
${LOCAL}/library/csi/csi-attacher:v1.1.1_vmware.7
${LOCAL}/library/csi/csi-livenessprobe:v1.1.0_vmware.7
${LOCAL}/library/csi/csi-node-driver-registrar:v1.1.0_vmware.7
${LOCAL}/library/csi/csi-provisioner:v1.4.0_vmware.2
${LOCAL}/library/csi/volume-metadata-syncer:v1.0.2_vmware.1
${LOCAL}/library/csi/vsphere-block-csi-driver:v1.0.2_vmware.1
${LOCAL}/library/cert-manager/cert-manager-controller:v0.11.0_vmware.1
${LOCAL}/library/cert-manager/cert-manager-cainjector:v0.11.0_vmware.1
${LOCAL}/library/cert-manager/cert-manager-webhook:v0.11.0_vmware.1
${LOCAL}/library/coredns:v1.6.7_vmware.1
${LOCAL}/library/etcd:v3.4.3_vmware.5
${LOCAL}/library/kube-apiserver:v1.18.2_vmware.1
${LOCAL}/library/kube-controller-manager:v1.18.2_vmware.1
${LOCAL}/library/kube-proxy:v1.18.2_vmware.1
${LOCAL}/library/kube-scheduler:v1.18.2_vmware.1
${LOCAL}/library/pause:3.2
EOF

find /root/.tkg/ -type f | xargs sed -i  's/registry\.tkg\.vmware\.run/harbor.vmwarelab.edu/g'


