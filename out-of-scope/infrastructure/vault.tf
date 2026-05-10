# Enable it later once we have the asana key
resource "azurerm_key_vault" "ddg_asana_key" {
  #count                       = 1
  name                        = "ddg-asana-key"
  location                    = azurerm_resource_group.ddg_group.location
  resource_group_name         = azurerm_resource_group.ddg_group.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current_environment.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"
}

resource "azurerm_key_vault_access_policy" "admin_policy" {
  count        = length(azurerm_key_vault.ddg_asana_key) # Only exists if KV exists
  key_vault_id = azurerm_key_vault.ddg_asana_key[0].id
  tenant_id    = data.azurerm_client_config.current_environment.tenant_id
  object_id    = data.azurerm_client_config.current_environment.object_id

  key_permissions    = ["Get", "List", "Create", "Delete"]
  secret_permissions = ["Get", "List", "Set", "Delete"]
}

resource "azurerm_key_vault_access_policy" "vm_policy" {
  # This will loop based on how many VMs exist
  count        = length(azurerm_linux_virtual_machine.app_vm) * length(azurerm_key_vault.ddg_asana_key)
  key_vault_id = azurerm_key_vault.ddg_asana_key[0].id
  tenant_id    = data.azurerm_client_config.current_environment.tenant_id

  # Correct syntax for reaching into the identity list
  object_id = azurerm_linux_virtual_machine.app_vm[count.index].identity[0].principal_id

  secret_permissions = ["Get", "List"]
}
