# Virtual Network
resource "azurerm_virtual_network" "ddg_vn" {
  name                = "ddg-vn"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name
  address_space       = ["10.0.0.0/16"]
}

# VM subnet
resource "azurerm_subnet" "vm_subnet" {
  name                 = "vm-subnet"
  resource_group_name = azurerm_resource_group.ddg_group.name
  virtual_network_name = azurerm_virtual_network.ddg_vn.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Database subnet
resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.ddg_group.name
  virtual_network_name = azurerm_virtual_network.ddg_vn.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "db_dns" {
  name                = "ddg-edgar.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.ddg_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "db_vnet_link" {
  name                  = "db-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.db_dns.name
  virtual_network_id    = azurerm_virtual_network.ddg_vn.id
  resource_group_name = azurerm_resource_group.ddg_group.name
  depends_on            = [azurerm_subnet.db_subnet]
}
