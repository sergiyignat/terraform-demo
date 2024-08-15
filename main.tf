/*This is a sample demo just to reach the target goals of the task (create Terraform definition to run a Dockerized service inside Azure Container Apps, protected by Azure Application Gateway WAF). 
So there are no modules which can be re-used, because there is no need of them so far (eg https://github.com/antonbabenko/terraform-best-practices/tree/master/examples/small-terraform).
Also, varaible list can be extended but I suppose it's enough for this demo.*/

locals {
  default_tags = {
    environment = var.env
    owner       = "Sergio"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-${var.env}-rg"
  location = var.region
  tags     = local.default_tags
}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "${var.prefix}-${var.env}-laws"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.default_tags
}

resource "azurerm_container_app_environment" "aca_env" {
  name                           = "${var.prefix}-${var.env}-env"
  location                       = azurerm_resource_group.rg.location
  resource_group_name            = azurerm_resource_group.rg.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_analytics_workspace.id
  infrastructure_subnet_id       = azurerm_subnet.backend.id
  internal_load_balancer_enabled = "true"
  depends_on                     = [azurerm_virtual_network.vnet]
  tags                           = local.default_tags
}
resource "azurerm_container_app" "aca_app" {
  name                         = "${var.prefix}-${var.env}-app"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = local.default_tags

  template {
    container {
      name   = "aca-demo-app"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1.0Gi"
    }
    min_replicas = "1"
    max_replicas = "1"
  }

  ingress {
    allow_insecure_connections = true
    external_enabled           = true
    target_port                = 80

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-${var.env}-VNet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.21.0.0/16"]
  tags                = local.default_tags
}

resource "azurerm_subnet" "AGSubnet" {
  name                 = "${var.prefix}-${var.env}-AGSubnetSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.0.0/23"]
}

resource "azurerm_subnet" "backend" {
  name                 = "${var.prefix}-${var.env}-BackendSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.2.0/23"]
}

resource "azurerm_public_ip" "pip" {
  name                = "${var.prefix}-${var.env}-AGPublicIPAddress"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}

resource "azurerm_application_gateway" "application_gateway" {
  name                = "${var.prefix}-${var.env}-myAppGateway"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  depends_on          = [azurerm_container_app.aca_app]
  tags                = local.default_tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway_ip_configuration"
    subnet_id = azurerm_subnet.AGSubnet.id
  }

  frontend_port {
    name = "frontend_port_name"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend_ip_configuration_name"
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  backend_address_pool {
    name  = "backend_address_pool_name"
    fqdns = [azurerm_container_app.aca_app.ingress[0].fqdn]
  }

  backend_http_settings {
    name                                = "http_setting_name"
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 60
    pick_host_name_from_backend_address = "true"
  }

  http_listener {
    name                           = "listener_name"
    frontend_ip_configuration_name = "frontend_ip_configuration_name"
    frontend_port_name             = "frontend_port_name"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "request_routing_rule_name"
    rule_type                  = "Basic"
    http_listener_name         = "listener_name"
    backend_address_pool_name  = "backend_address_pool_name"
    backend_http_settings_name = "http_setting_name"
    priority                   = 1
  }

  waf_configuration {
    firewall_mode            = "Detection"
    rule_set_version         = "3.1"
    file_upload_limit_mb     = 100
    max_request_body_size_kb = 128
    enabled                  = "true"
    /*
    disabled_rule_group = [
      {
        rule_group_name = "REQUEST-930-APPLICATION-ATTACK-LFI"
        rules           = ["930100", "930110"]
      },
      {
        rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
        rules           = ["920160"]
      }
    ]

    exclusion = [
      {
        match_variable          = "RequestCookieNames"
        selector                = "SomeCookie"
        selector_match_operator = "Equals"
      },
      {
        match_variable          = "RequestHeaderNames"
        selector                = "referer"
        selector_match_operator = "Equals"
      }
    ]*/
  }
}

resource "azurerm_private_dns_zone" "pdz" {
  name                = regex("[a-z1-9-]*.[a-z]*.[a-z]*.[a-z]*$", azurerm_container_app.aca_app.ingress[0].fqdn)
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.default_tags
  depends_on          = [azurerm_container_app.aca_app]
}

resource "azurerm_private_dns_a_record" "starRecord" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.pdz.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.aca_env.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "pdz_private_link" {
  name                  = "pdz_private_link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pdz.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = local.default_tags
}
