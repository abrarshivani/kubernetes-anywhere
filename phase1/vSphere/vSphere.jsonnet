function(config)
  local tf = import "phase1/tf.jsonnet";
  local cfg = config.phase1;
  local vms = std.makeArray(cfg.num_nodes,function(node) node+1); 
  local kubeconfig(user, cluster, context) =
    std.manifestJson(
      tf.pki.kubeconfig_from_certs(
        user, cluster, context,
        cfg.cluster_name + "-root",
        "https://${vsphere_virtual_machine.kubedebian1.network_interface.0.ipv4_address}",
      ));
  local config_metadata_template = std.toString(config {
      master_ip: "${vsphere_virtual_machine.kubedebian1.network_interface.0.ipv4_address}",
      role: "%s",
      phase3 +: {
        addons_config: (import "phase3/all.jsonnet")(config),
      },
    });
  
  std.mergePatch({
    provider: {
      vsphere: {
        user: cfg.vSphere.username,
        password: cfg.vSphere.password,
        vsphere_server: cfg.vSphere.url,
        allow_unverified_ssl: cfg.vSphere.insecure,
      },
    },
    
     data: {
      template_file: {
        configure_master: {
          template: "${file(\"configure-vm.sh\")}",
          vars: {
            role: "master",
            root_ca_public_pem: "${base64encode(tls_self_signed_cert.%s-root.cert_pem)}" % cfg.cluster_name,
            apiserver_cert_pem: "${base64encode(tls_locally_signed_cert.%s-master.cert_pem)}" % cfg.cluster_name,
            apiserver_key_pem: "${base64encode(tls_private_key.%s-master.private_key_pem)}" % cfg.cluster_name,
            node_kubeconfig: kubeconfig(cfg.cluster_name + "-node", "local", "service-account-context"),
            master_kubeconfig: kubeconfig(cfg.cluster_name + "-master", "local", "service-account-context"),
          },
        },
        cloudprovider: {
          template: "${file(\"vsphere.conf\")}",
          vars: {
            username: cfg.vSphere.username,
            password: cfg.vSphere.password,
            vsphere_server: cfg.vSphere.url,
            port: cfg.vSphere.port,
            allow_unverified_ssl: cfg.vSphere.insecure,
            datacenter: cfg.vSphere.datacenter,
            datastore: cfg.vSphere.datastore,
          },
        },
      },
    },

    
    resource: {
      vsphere_virtual_machine: {
        ["kubedebian" + vm]: {
            name: "kubedebian%d" % vm,
            vcpu: 2,
            memory: 2048,
            enable_disk_uuid: true,
            datacenter: cfg.vSphere.datacenter,

            network_interface: {
              label: "VM Network",
            },
            disk: {
              datastore: cfg.vSphere.datastore, 
              vmdk:"kube/kube%d.vmdk/kube.vmdk" % vm ,
              bootable: true,
            },
        } for vm in vms
      },
      null_resource: {
        myvm: {
            depends_on: ["vsphere_virtual_machine.kubedebian1"],
            connection: {
              user: "kube",
              password: "kube",
              host: "${vsphere_virtual_machine.kubedebian1.network_interface.0.ipv4_address}"
            },
            provisioner: [{
                "remote-exec": {
                  inline: [
                    "sudo echo '%s' > /home/kube/k8s_config.json" % (config_metadata_template % "master"),
                    "sudo mkdir -p /etc/kubernetes/",
                    "sleep 4; sudo cp /home/kube/k8s_config.json /etc/kubernetes/ ",
                    "echo '%s' > /home/kube/configure-vm.sh" % "${data.template_file.configure_master.rendered}",
                    "sleep 2; sudo bash /home/kube/configure-vm.sh",
                    "echo '%s' > /home/kube/vsphere.conf" % "${data.template_file.cloudprovider.rendered}",
                    "sudo cp /home/kube/vsphere.conf /etc/kubernetes/vsphere.conf",

                  ]
                }
           }, {
            "local-exec": {
              command: "echo '%s' > ./.tmp/kubeconfig.json" % kubeconfig(cfg.cluster_name + "-admin", cfg.cluster_name, cfg.cluster_name),
            },
           }],
        },
      },    
    },
  }, tf.pki.cluster_tls(cfg.cluster_name, ["%(cluster_name)s-master" % cfg], ["${vsphere_virtual_machine.kubedebian1.network_interface.0.ipv4_address}"]))