# Create a Public IP
resource "azurerm_public_ip" "vm_public_ip" {
  count               = local.vms
  name                = "pip-app-vm"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name
  allocation_method   = "Dynamic"
}

# Virtual Network Interface (NIC) for the VM
resource "azurerm_network_interface" "vm_vnic" {
  count               = local.vms
  name                = "vm_vnic"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id # Connecting to the VM Subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip[count.index].id
  }
}

# Only allow SSH (Port 22) into this subnet
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "vm-nsg"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # This needs to be modified to set the source IP
    destination_address_prefix = "*"
  }
}

# Associate NSG with the VM Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Linux Virtual Machine(s)
resource "azurerm_linux_virtual_machine" "app_vm" {
  count               = local.vms
  name                = "vm-server${count.index + 1}"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name
  size                = "Standard_B1s" # Free Tier
  identity {
    type = "SystemAssigned"
  }
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.vm_vnic[count.index].id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/edgardl_laptop.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  # Chef Solo (for testing purposes); this would normally be handled by a Chef server
  custom_data = base64encode(<<-EOF
  #!/bin/bash
  # Install Chef
  curl -L https://chef.io | sudo bash

  # Create the attributes file for Chef Solo
  mkdir -p /var/chef/nodes
  cat <<EON > /var/chef/node.json
  {
    "github_token": "${var.github_token}",
    "github_user": "${var.github_user}",
    "github_repo_name": "${var.your-repo-name}",
    "db_host": "${azurerm_postgresql_flexible_server.feedback_db_server.fqdn}",
    "db_name": "${azurerm_postgresql_flexible_server_database.feedback_db.name}",
    "db_feedback_table": "${var.db_feedback_table}"
  }
  EON

  # Create the cookbook directory
  mkdir -p /var/chef/cookbooks/feedback_app/recipes
  # Load recipe
  cat <<EOR > /var/chef/cookbooks/feedback_app/recipes/default.rb
  ${file("${path.module}/chef/default.rb")}
  EOR

  # Run Chef Solo using the local node.json attributes
  chef-client --local-mode -j /var/chef/node.json --runlist 'recipe[feedback_app]'
 EOF
  )

}
