function(config)
  local tf = import "phase1/tf.jsonnet";
  local cfg = config.phase1;
  local vms = std.makeArray(cfg.num_nodes,function(x) x+1); 
  
  {
    provider: {
      vsphere: {
        user: cfg.vSphere.username,
        password: cfg.vSphere.password,
        vsphere_server: cfg.vSphere.url,
        allow_unverified_ssl: cfg.vSphere.insecure,
      },
    },
  
    
    resource: {
      vsphere_file: {
        ["upload_kube_vmdk"]: {
            datacenter: cfg.vSphere.datacenter,
            datastore: cfg.vSphere.datastore,
            source_file: "/opt/kubernetes-anywhere/phase1/vSphere/kube.vmdk",
            destination_file: "kube/kube.vmdk"
        }
      } + { 
      ["kube_disk_copy" + vm]: {
            depends_on: ["vsphere_file.upload_kube_vmdk"],
            source_datacenter: cfg.vSphere.datacenter,
            datacenter: cfg.vSphere.datacenter,
            source_datastore: cfg.vSphere.datastore,
            datastore: cfg.vSphere.datastore,
            source_file: "kube/kube.vmdk",
            destination_file: "kube/kube%d.vmdk" % vm,
        }  for vm in vms }, 
      vsphere_virtual_machine: {
        ["kube_debian" + vm]: {
            depends_on: ["vsphere_file.kube_disk_copy%d" % vm],
            name: "kube%d" % vm,
            vcpu: 2,
            memory: 2048,
            enable_disk_uuid: true,
            datacenter: cfg.vSphere.datacenter,

            network_interface: {
              label: "VM Network",
            },
            disk: {
              datastore: cfg.vSphere.datastore, 
              vmdk:"kube/kube%d.vmdk" % vm ,
              bootable: true,
            },
        } for vm in vms
      },
    },
  }