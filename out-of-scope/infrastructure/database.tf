resource "azurerm_postgresql_flexible_server" "feedback_db_server" {
  name                = "feedback-db-server"
  resource_group_name = azurerm_resource_group.ddg_group.name
  location            = azurerm_resource_group.ddg_group.location
  version             = "13"
  # Connect the server to the delegated subnet and DNS zone
  delegated_subnet_id = azurerm_subnet.db_subnet.id
  private_dns_zone_id = azurerm_private_dns_zone.db_dns.id

  # Enable Entra ID authentication and disable password access
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
  }
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
}

resource "azurerm_postgresql_flexible_server_database" "feedback_db" {
  name      = "feedback-db"
  server_id = azurerm_postgresql_flexible_server.feedback_db_server.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# Assign an Entra ID admin to the server
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "db_ad" {
  server_name         = azurerm_postgresql_flexible_server.feedback_db_server.name
  resource_group_name = azurerm_resource_group.ddg_group.name
  tenant_id           = data.azurerm_client_config.current_environment.tenant_id
  object_id           = data.azurerm_client_config.current_environment.object_id
  # Terraform doesn't do a good job guessing this so it's best to manually enter it
  principal_name      = "edgar_dorantes_@hotmail.com"
  principal_type      = "User"
}
