provider "azurerm" {
  version = "~> 1.0"
}

provider "template" {
  version = "~> 1.0"
}

module "os" {
  source       = "./os"
  vm_os_simple = "${var.vm_os_simple}"
}

resource "azurerm_resource_group" "vmss" {
  name     = "${var.resource_group_name}"
  location = "${var.location}"
  tags     = "${var.tags}"
}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "test" {
  name     = "${var.pl_rg}"
  location = "${var.pl_location}"
}

 resource "azurerm_virtual_network" "test" {
    name                = "${var.pl_vnet}"
    address_space       = ["${var.pl_vnet_addr_space}"]
    location            = "${azurerm_resource_group.test.location}"
    resource_group_name = "${azurerm_resource_group.test.name}"
}

 resource "azurerm_subnet" "test" {
    name                 = "${var.pl_subnet}"
    resource_group_name  = "${azurerm_resource_group.test.name}"
    virtual_network_name = "${azurerm_virtual_network.test.name}"
    address_prefix       = "${var.pl_subnet_prefix}"
    private_link_service_network_policies = "${var.pl_net_policy}"
    private_endpoint_network_policies = "${var.pe_net_policy}"
}

 resource "azurerm_public_ip" "test" {
    name                = "${var.pl_public_ip}"
    sku                 = "${var.pl_public_ip_sku}"
    location            = "${azurerm_resource_group.test.location}"
    resource_group_name = "${azurerm_resource_group.test.name}"
    allocation_method   = "${var.pl_public_ip_alloc}"
}

 resource "azurerm_lb" "test" {
    name                = "${var.pl_lb}"
    sku                 = "${var.pl_lb_sku}"
    location            = "${azurerm_resource_group.test.location}"
    resource_group_name = "${azurerm_resource_group.test.name}"
    frontend_ip_configuration {
        name                 = "${azurerm_public_ip.test.name}"
        public_ip_address_id = "${azurerm_public_ip.test.id}"
    }
}

resource "azurerm_private_endpoint" "test" {
  name                = "${var.pe_name}"
  location            = "${azurerm_resource_group.test.location}"
  resource_group_name = "${azurerm_resource_group.test.name}"
  subnet_id           = "${azurerm_subnet.test.id}"
  tags = {
    env = "test"
    version = "2"
  }

 manual_private_link_service_connections {
    name = "${var.pl_service_connection}"
    private_link_service_id = "${azurerm_private_link_service.test.id}"
    request_message         = "Please approve my connection."
  }
}

resource "azurerm_private_link_service" "test" {
   name = "${var.pl_service}"
   location = "${azurerm_resource_group.test.location}"
   resource_group_name = "${azurerm_resource_group.test.name}"
   fqdns = ["testFqdns"]
   ip_configuration {
     name = "${azurerm_public_ip.test.name}"
     subnet_id = "${azurerm_subnet.test.id}"
     private_ip_address = "${var.pl_service_pvt_ip}"
     private_ip_address_version = "${var.pl_service_pvt_ip_version}"
     private_ip_address_allocation = "${var.pl_service_pvt_ip_alloc}"
   }
   load_balancer_frontend_ip_configuration {
      id = "${azurerm_lb.test.frontend_ip_configuration.0.id}"
   }
   tags = {
     env = "test"
     version = "2"
   }
}
  
  
  
resource "azurerm_virtual_machine_scale_set" "vm-linux" {
  count               = "${var.nb_instance}"
  name                = "${var.vmscaleset_name}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vmss.name}"
  upgrade_policy_mode = "Manual"
  tags                = "${var.tags}"

  sku {
    name     = "${var.vm_size}"
    tier     = "Standard"
    capacity = "${var.nb_instance}"
  }

  storage_profile_image_reference {
    id        = "${var.vm_os_id}"
    publisher = "${coalesce(var.vm_os_publisher, module.os.calculated_value_os_publisher)}"
    offer     = "${coalesce(var.vm_os_offer, module.os.calculated_value_os_offer)}"
    sku       = "${coalesce(var.vm_os_sku, module.os.calculated_value_os_sku)}"
    version   = "${var.vm_os_version}"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "${var.managed_disk_type}"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = "${var.data_disk_size}"
  }

  os_profile {
    computer_name_prefix = "${var.computer_name_prefix}"
    admin_username       = "${var.admin_username}"
    admin_password       = "${var.admin_password}"
    #custom_data          = "${data.template_cloudinit_config.config.rendered}"
    custom_data          = "${var.custom_data}" 
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${file("${var.ssh_key}")}"
    }
  }

  network_profile {
    name    = "${var.network_profile}"
    primary = true

    ip_configuration {
  
      name                                   = "IPConfiguration"
      subnet_id                              = "${var.vnet_subnet_id}"
      primary                                = true
      load_balancer_backend_address_pool_ids = ["${var.load_balancer_backend_address_pool_ids}"]
      }
  }
}
