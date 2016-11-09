mkdir -p /srv/kubernetes

cat << EOF > "/etc/default/flannel"
    NETWORK=${flannel_net}
    ETCD_ENDPOINTS=http://${master_ip}:4000
EOF


if [ "${role}" == "master" ]; then
    # Download & Start etcd
    systemctl enable etcd
    # TODO: Setup etcd as systemd unit
    systemctl start etcd
    # Wait for etcd to start
    #while ! nc -q 1 "${master_ip}" 4000 </dev/null; do sleep 2; done                                           
    # Start flannel
    systemctl enable flanneld
    systemctl start flanneld
    # Create certificates on master
    echo -n "${root_ca_public_pem}" | base64 -d > "/srv/kubernetes/ca.pem"
    echo -n "${apiserver_cert_pem}" | base64 -d > "/srv/kubernetes/apiserver.pem"
    echo -n "${apiserver_key_pem}" | base64 -d > "/srv/kubernetes/apiserver-key.pem"
    # Create kubernetes configuration 
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${master_kubeconfig}
EOF
else
    systemctl enable flannelc
    systemctl start flannelc    
    cat << EOF > "/srv/kubernetes/kubeconfig.json"
    ${node_kubeconfig}
EOF
fi

# Add dns entries to /etc/hosts 
echo "${nodes_dns_mappings}" >> /etc/hosts

# Wait for etcd to be up
#while ! nc -q 1 "${master_ip}" 4000 </dev/null; do sleep 2; done

systemctl enable docker
systemctl start docker
docker run \
  --net=host \
  -v /:/mnt/root \
  -v /run:/run \
  -v /etc/kubernetes:/etc/kubernetes \
  -v /var/lib/ignition:/usr/share/oem \
  "${installer_container}" /bin/do_role
systemctl daemon-reload
systemctl start kubelet.service