output "k3s_nodes" {
  description = "The provisioned k3s VMs"
  value = {
    for k, vm in proxmox_virtual_environment_vm.k3s :
    k => {
      name  = vm.name
      node  = vm.node_name
      vm_id = vm.vm_id
      ip    = local.nodes[k].ip
    }
  }
}
