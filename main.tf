terraform {
	required_version = "~> 0.12"
}
provider "azurerm" {
	client_id = var.client_id
	tenant_id = var.tenant_id
	subscription_id = var.subscription_id
	client_secret = var.client_secret
}
resource "azurerm_resource_group" "my-group" {
	name     = "terraform"
	location = var.location
}
resource "azurerm_virtual_machine" "my-compute" {
	name = "terraformvm"
	count = var.web_instance_count
	location = var.location
	resource_group_name = azurerm_resource_group.my-group.name
	network_interface_ids = [azurerm_network_interface.my-nw-interface.*.id[count.index]]
	vm_size = "Standard_B2ms"
	os_profile {
		computer_name = "terraformvm"
		admin_username = var.admin_username
		admin_password = var.admin_password
	}
	os_profile_linux_config {
		disable_password_authentication = false
	}
	tags = {
		environment = "terraform"
	}
	storage_image_reference {
		publisher = "Canonical"
		offer = "UbuntuServer"
		sku = "16.04-LTS"
		version = "latest"
	}
	storage_os_disk {
		name = "terraformdisk"
		caching = "ReadWrite"
		create_option = "FromImage"
		managed_disk_type = "Standard_LRS"
		disk_size_gb = "50"
	}
}
resource "azurerm_virtual_network" "my-vnet" {
	name                = "terraformvnet"
	address_space       = ["10.0.0.0/16"]
	location            = var.location
	resource_group_name   = azurerm_resource_group.my-group.name
}
resource "azurerm_subnet" "my-subnet" {
	name                 = "terraformsubnet"
	resource_group_name   = azurerm_resource_group.my-group.name
	virtual_network_name = azurerm_virtual_network.my-vnet.name
	address_prefix       = "10.0.2.0/24"
}
resource "azurerm_network_interface" "my-nw-interface" {
	name                = "terraforminterface"
	count = var.web_instance_count
	location            = var.location
	resource_group_name   = azurerm_resource_group.my-group.name
	ip_configuration {
		name = "terraformipconfig"
		subnet_id = azurerm_subnet.my-subnet.id
		private_ip_address_allocation = "Dynamic"
	}
}
resource "azurerm_network_interface_backend_address_pool_association" "my-nw-if-be-addr-pool-association" {
	network_interface_id    = azurerm_network_interface.my-nw-interface.*.id[count.index]
	ip_configuration_name   = "terraformipconfig"
	backend_address_pool_id = azurerm_lb_backend_address_pool.my-lb-addr-pool.id
	count = var.web_instance_count
}
resource "azurerm_public_ip" "my-public-ip" {
	name                = "terraformpublicip"
	location            = var.location
	resource_group_name = azurerm_resource_group.my-group.name
	allocation_method   = "Static"
}
resource "azurerm_lb" "my-lb" {
	name                = "terraformlb"
	location            = var.location
	resource_group_name = azurerm_resource_group.my-group.name
	frontend_ip_configuration {
		name                 = "terraformfrontip"
		public_ip_address_id = azurerm_public_ip.my-public-ip.id
	}
}
resource "azurerm_lb_backend_address_pool" "my-lb-addr-pool" {
	resource_group_name = azurerm_resource_group.my-group.name
	loadbalancer_id     = azurerm_lb.my-lb.id
	name                = "terraformlbaddrpool"
}
resource "azurerm_lb_nat_rule" "ssh-nat-rule" {
	resource_group_name            = azurerm_resource_group.my-group.name
	loadbalancer_id                = azurerm_lb.my-lb.id
	name                           = "ssh-nat-rule"
	protocol                       = "Tcp"
	frontend_port                  = 22
	backend_port                   = 22
	frontend_ip_configuration_name = azurerm_lb.my-lb.frontend_ip_configuration[0].name
}
resource "azurerm_lb_nat_rule" "http-nat-rule" {
	resource_group_name            = azurerm_resource_group.my-group.name
	loadbalancer_id                = azurerm_lb.my-lb.id
	name                           = "http-nat-rule"
	protocol                       = "Tcp"
	frontend_port                  = 8800
	backend_port                   = 8800
	frontend_ip_configuration_name = azurerm_lb.my-lb.frontend_ip_configuration[0].name
}
resource "azurerm_lb_nat_rule" "https-nat-rule" {
	resource_group_name            = azurerm_resource_group.my-group.name
	loadbalancer_id                = azurerm_lb.my-lb.id
	name                           = "https-nat-rule"
	protocol                       = "Tcp"
	frontend_port                  = 443
	backend_port                   = 443
	frontend_ip_configuration_name = azurerm_lb.my-lb.frontend_ip_configuration[0].name
}
resource "azurerm_network_interface_nat_rule_association" "ssh-nat-association" {
	count = var.web_instance_count
	network_interface_id  = azurerm_network_interface.my-nw-interface[count.index].id
	ip_configuration_name = "terraformipconfig"
	nat_rule_id           = azurerm_lb_nat_rule.ssh-nat-rule.id
}
resource "azurerm_network_interface_nat_rule_association" "https-nat-association" {
	count = var.web_instance_count
	network_interface_id  = azurerm_network_interface.my-nw-interface[count.index].id
	ip_configuration_name = "terraformipconfig"
	nat_rule_id           = azurerm_lb_nat_rule.https-nat-rule.id
}
resource "azurerm_network_interface_nat_rule_association" "http-nat-association" {
	count = var.web_instance_count
	network_interface_id  = azurerm_network_interface.my-nw-interface[count.index].id
	ip_configuration_name = "terraformipconfig"
	nat_rule_id           = azurerm_lb_nat_rule.http-nat-rule.id
}
resource "azurerm_network_security_group" "my-sg" {
	name                = "terraformsg"
	location            = var.location
	resource_group_name = azurerm_resource_group.my-group.name
}
resource "azurerm_network_security_rule" "ssh-security-rule" {
	name                       = "ssh"
	priority                   = 100
	direction                  = "Inbound"
	access                     = "Allow"
	protocol                   = "Tcp"
	source_port_range          = "*"
	destination_port_range     = "22"
	source_address_prefix      = "*"
	destination_address_prefix = "*"
	network_security_group_name = azurerm_network_security_group.my-sg.name
	resource_group_name = azurerm_resource_group.my-group.name
}
resource "azurerm_network_security_rule" "http-security-rule" {
	name                       = "ssh"
	priority                   = 100
	direction                  = "Inbound"
	access                     = "Allow"
	protocol                   = "Tcp"
	source_port_range          = "*"
	destination_port_range     = "8800"
	source_address_prefix      = "*"
	destination_address_prefix = "*"
	network_security_group_name = azurerm_network_security_group.my-sg.name
	resource_group_name = azurerm_resource_group.my-group.name
}
resource "azurerm_network_security_rule" "https-security-rule" {
	name                       = "ssh"
	priority                   = 100
	direction                  = "Inbound"
	access                     = "Allow"
	protocol                   = "Tcp"
	source_port_range          = "*"
	destination_port_range     = "443"
	source_address_prefix      = "*"
	destination_address_prefix = "*"
	network_security_group_name = azurerm_network_security_group.my-sg.name
	resource_group_name = azurerm_resource_group.my-group.name
}