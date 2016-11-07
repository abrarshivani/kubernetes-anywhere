mkdir -p /srv/kubernetes

if [ "${role}" == "master" ]; then
    # Download kubectl
    wget -P /usr/local/bin/ https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl
    chmod 777 /usr/local/bin/kubectl
    # Download & Start etcd
    wget https://github.com/coreos/etcd/releases/download/v3.0.13/etcd-v3.0.13-linux-amd64.tar.gz
    tar -xvf etcd-v3.0.13-linux-amd64.tar.gz
    cd etcd-v3.0.13-linux-amd64
    # TODO: Setup etcd as systemd unit
    nohup ./etcd --listen-client-urls http://0.0.0.0:4000 --listen-peer-urls http://0.0.0.0:4001 --advertise-client-urls http://0.0.0.0:4000 &
    # Wait for etcd to start
    while ! nc -q 1 "${master_ip}" 4000 </dev/null; do sleep 2; done                                           
    # Set network config for flannel
    ./etcdctl --endpoints="http://0.0.0.0:4000"  set /coreos.com/network/config ' "'"'{' '"Network"'':' '"172.1.0.0/16"' '}'"'" '                                                  
    ./etcdctl --endpoints="http://0.0.0.0:4000" get /coreos.com/network/config
    cd ..
    # Create certificates on master
    echo -n "${root_ca_public_pem}" | base64 -d > "/srv/kubernetes/ca.pem"
    echo -n "${apiserver_cert_pem}" | base64 -d > "/srv/kubernetes/apiserver.pem"
    echo -n "${apiserver_key_pem}" | base64 -d > "/srv/kubernetes/apiserver-key.pem"
    # Create kubernetes configuration 
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${master_kubeconfig}
EOF
else
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${node_kubeconfig}
EOF
fi

# Add dns entries to /etc/hosts 
echo "${nodes_dns_mappings}" >> /etc/hosts



# Download & Extract flannel
wget https://github.com/coreos/flannel/releases/download/v0.6.2/flannel-v0.6.2-linux-amd64.tar.gz
tar -xvf flannel-v0.6.2-linux-amd64.tar.gz

# Get VM IP 
vm_ip=$(ip addr | grep' "'"'state UP'"'" '-A2 | tail -n1 | awk' "'"'{print $2}'"'" '| cut -f1  -d'"'"/"'"')

# Wait for etcd to be up
while ! nc -q 1 "${master_ip}" 4000 </dev/null; do sleep 2; done

# Setup flannel
# TODO: Setup flannel as systemd unit
nohup ./flanneld --etcd-endpoints="http://${master_ip}:4000"  --ip-masq  --iface="$vm_ip" &
while ! [ -f /var/run/flannel/subnet.env ]; do
          sleep 2
       done

if [ -f /var/run/flannel/subnet.env ]; then
          . /var/run/flannel/subnet.env
        fi

mkdir -p /etc/systemd/system/docker.service.d/
cat <<EOF > /etc/systemd/system/docker.service.d/clear_mount_propagation_flags.conf
[Service]
MountFlags=shared
EOF

# start hacky workaround (https://github.com/docker/docker/issues/23793)
  curl -sSL https://get.docker.com/ > /tmp/install-docker
  chmod +x /tmp/install-docker
  /tmp/install-docker || true
  systemctl start docker || true
# end hacky workaround

# Append FLANNEL_OPTS to DOCKER_OPTS
sed -i "/ExecStart/s,$, --bip="$FLANNEL_SUBNET" --mtu="$FLANNEL_MTU" ," /lib/systemd/system/docker.service

# Reload docker & Start phase2
sudo groupadd docker
sudo gpasswd -a kube docker
sudo systemctl daemon-reload
sudo systemctl restart docker.service
docker run \
  --net=host \
  -v /:/mnt/root \
  -v /run:/run \
  -v /etc/kubernetes:/etc/kubernetes \
  -v /var/lib/ignition:/usr/share/oem \
  ashivani/k8s-ignition:v3 /bin/do_role
systemctl daemon-reload
systemctl start kubelet.service