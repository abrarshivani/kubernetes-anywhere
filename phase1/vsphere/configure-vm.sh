mkdir -p /srv/kubernetes

if [ "${role}" == "master" ]; then
    echo -n "${root_ca_public_pem}" | base64 -d > "/srv/kubernetes/ca.pem"
    echo -n "${apiserver_cert_pem}" | base64 -d > "/srv/kubernetes/apiserver.pem"
    echo -n "${apiserver_key_pem}" | base64 -d > "/srv/kubernetes/apiserver-key.pem"
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${master_kubeconfig}
    wget -P /usr/local/bin/ https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl
    chmod 777 /usr/local/bin/kubectl
EOF
else
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${node_kubeconfig}
EOF
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

sudo groupadd docker
sudo gpasswd -a kube docker
sudo service docker restart
docker run \
  --net=host \
  -v /:/mnt/root \
  -v /run:/run \
  -v /etc/kubernetes:/etc/kubernetes \
  -v /var/lib/ignition:/usr/share/oem \
  ashivani/k8s-ignition:v2 /bin/do_role
systemctl daemon-reload
systemctl start kubelet.service