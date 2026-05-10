# Load Balancer -> It's only needed if we increase the number of VMs. For a single VM there's no point on having it for now
resource "azurerm_lb" "ddg_feedback_lb" {
  count               = 0
  name                = "ddg-feedback-lb"
  location            = azurerm_resource_group.ddg_group.location
  resource_group_name = azurerm_resource_group.ddg_group.name
  sku                 = "Basic" # <--- Basic to avoid charges

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vm_public_ip[0].id
  }
}
