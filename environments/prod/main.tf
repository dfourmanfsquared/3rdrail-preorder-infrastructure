locals {
  environment = "prod"
  project     = "thirdrail"
  location    = "centralus"

  common_tags = {
    ManagedBy   = "terraform"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "thirdrail_rg" {
  name     = "thirdrail-${local.environment}-rg"
  location = local.location
  tags = local.common_tags
}

resource "azurerm_service_plan" "thirdrail_sp" {
  name                = "thirdrail-${local.environment}-sp"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  location            = azurerm_resource_group.thirdrail_rg.location
  os_type             = "Linux"
  sku_name            = "P0V3"
}

# Azure Static Web App for payment portal frontend
resource "azurerm_static_web_app" "thirdrail_portal" {
  name                = "thirdrail-portal-${local.environment}"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  location            = local.location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = local.common_tags
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

resource "azurerm_cosmosdb_account" "cosmosaccount" {
  name                = "thirdraildb-${random_integer.ri.result}"
  location            = azurerm_resource_group.thirdrail_rg.location
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"


  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = local.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "cosmos-sql-db" {
  name                = "thirdrail-cosmos-sql-db"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  account_name        = azurerm_cosmosdb_account.cosmosaccount.name
  throughput          = 400
}

resource "azurerm_linux_web_app" "thirdrail-service-app" {
  name                = "thirdrail-app-${local.environment}"
  resource_group_name      = azurerm_resource_group.thirdrail_rg.name
  location                 = azurerm_resource_group.thirdrail_rg.location
  service_plan_id     = azurerm_service_plan.thirdrail_sp.id

  site_config {
    use_32_bit_worker = true
    always_on = true
    application_stack  {
      java_server         = "JAVA"
      java_server_version = "21" 
      java_version        = "21" 
    }
    health_check_path = "/health"
    health_check_eviction_time_in_min = 5
  }

app_settings ={

    "AZURE_VAULT_URI" = azurerm_key_vault.vault.vault_uri
}

  identity {
    type = "SystemAssigned"
  }

  logs{
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 30
        retention_in_mb = 35
      }
    }
  }
}


resource "azurerm_key_vault" "vault" {
  name                        = "thirdrail-vault2-${local.environment}"
  resource_group_name      = azurerm_resource_group.thirdrail_rg.name
  location                 = azurerm_resource_group.thirdrail_rg.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  network_acls {
    default_action = "Allow"
    bypass = "AzureServices"
  }
  purge_protection_enabled = true
}

resource "azurerm_key_vault_access_policy" "terraform-access-policy" {
  key_vault_id = azurerm_key_vault.vault.id
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = "${data.azurerm_client_config.current.object_id}"

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover"
    ]

    certificate_permissions = [
      "Get",
      "List",
      "Delete",
      "Create",
      "Import",
      "Update",
      "ManageContacts",
      "GetIssuers",
      "ListIssuers",
      "SetIssuers",
      "DeleteIssuers",
      "ManageIssuers",
      "Recover",
      "Purge"
    ]
}

resource "azurerm_key_vault_secret" "cosmos-db-endpoint" {
  name         = "COSMOS-ENDPOINT"
  value        = azurerm_cosmosdb_account.cosmosaccount.endpoint
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
    ]
}

resource "azurerm_key_vault_secret" "thirdrail-cosmos-key" {
  name         = "COSMOS-KEY"
  value        = azurerm_cosmosdb_account.cosmosaccount.primary_key
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_access_policy" "thirdrail-service-policy" {
  key_vault_id = azurerm_key_vault.vault.id
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = azurerm_linux_web_app.thirdrail-service-app.identity.*.principal_id[0]
    secret_permissions = [
      "Get",
      "List"
    ]

}

resource "azurerm_key_vault_access_policy" "daniel-access-policy" {
  key_vault_id = azurerm_key_vault.vault.id
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = "f711253b-6afe-4c8a-ac8a-4984a73c57b0"  # Daniel's object ID

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover"
    ]

}

resource "azurerm_key_vault_secret" "static-webapp-url" {
  name         = "STATIC-WEBSITE-BASE-URL"
  value        = "https://${azurerm_static_web_app.thirdrail_portal.default_host_name}"
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_secret" "WIX-api-key" {
  name         = "WIX-API-KEY"
  value        = "IST.eyJraWQiOiJQb3pIX2FDMiIsImFsZyI6IlJTMjU2In0.eyJkYXRhIjoie1wiaWRcIjpcIjhlMDMzZGE2LWMyYmMtNDI5NS05ODQ5LWVjNjc2NTg1MGQ0ZFwiLFwiaWRlbnRpdHlcIjp7XCJ0eXBlXCI6XCJhcHBsaWNhdGlvblwiLFwiaWRcIjpcImY4YmM4YmM1LTc4NTQtNGRjYy04Y2UyLTNlYTZjNGY3OTczMFwifSxcInRlbmFudFwiOntcInR5cGVcIjpcImFjY291bnRcIixcImlkXCI6XCI1NTk0ZTQ3Zi00MzNhLTRkNjgtOTE3YS1iNzE5ZTU2MWRiMDFcIn19IiwiaWF0IjoxNzY2OTM5ODIwfQ.WTvlceICU0CQfSMrEd9P8KWIHIWtAW2sMs5TwZI9WuYs9e9p6msAgyCXPsxcw2fR4E1Yw3GlkP007mKOk4acgjzyK0WQ9awzlDwhQbfI6EdzcboAIjlljfu9eBWkPP-CZTBpvFTnl8cnkpqvBpt8g-wsmD7KDE_eqcVrrVBNbDJEyEf8Cv2-FTjh-HwahTqcRnngcOw6WRCp0uoNPCbIiqXSZhqRCA6ljp87EIUrySheza4SINi8cz2rttObPL1NbilwCLjuHqeBlfzHRkDHNqd9f8ygu-0myOw5hVt4-0QJtp8DSmq9RlGDCTEJkg5DZ66MVCDS0jPMIMRwFztNJw"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "WIX-site-id" {
  name         = "WIX-SITE-ID"
  value        = "49bd8033-547b-411e-81e5-644d8a2b4692"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-api-login-id" {
  name         = "AUTHORIZENET-API-LOGIN-ID"
  value        = "7SL5ke25"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-transaction-key" {
  name         = "AUTHORIZENET-TRANSACTION-KEY"
  value        = "9Q942kX5dwU3y353"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-environment" {
  name         = "AUTHORIZENET-ENVIRONMENT"
  value        = "sandbox"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-client-key" {
  name         = "AUTHORIZENET-CLIENT-KEY"
  value        = "5Wjac683WVdza2DGzxHu68jDP37ERGYz98wPVUKhvtM6e438MapP9L6zFZgwNk3F"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

#LIVE AciPv-bQ1ZLnqGKMYQUQ7kxCN9RhnxY10C5UX55YKKTpa3yCrh7gJejKpuB38txKfKk_LHd7WTnSrg6W
resource "azurerm_key_vault_secret" "paypal-client-id-secret" {
  name         = "PAYPAL-CLIENT-ID"
  value        = "AUwDTyJ7Ob8XKbR4S8WRqKBfX4q2GNFZw5g1SQ-78OntXj9BSXR6rY-vF5zFz1FYbZbUYlW9Ab7xxqir"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

#LIVE ENGz8_7mkCMf1fjFXHhFxrh3PPpKbRm81kR0H04v1onwigVbrXSXmZVZCzQOKrfvF1TNlH03U0yq_WTD
resource "azurerm_key_vault_secret" "paypal-client-secret" {
  name         = "PAYPAL-CLIENT-SECRET"
  value        = "AUwDTyJ7Ob8XKbR4S8WRqKBfX4q2GNFZw5g1SQ-78OntXj9BSXR6rY-vF5zFz1FYbZbUYlW9Ab7xxqir"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

resource "azurerm_key_vault_secret" "paypal-environment-secret" {
  name         = "PAYPAL-ENVIRONMENT"
  value        = "sandbox"
  key_vault_id = "${azurerm_key_vault.vault.id}"
  depends_on   = [azurerm_key_vault_access_policy.terraform-access-policy]
}

# Azure Front Door for custom domain on static website (replaces deprecated CDN)
resource "azurerm_cdn_frontdoor_profile" "thirdrail_frontdoor" {
  name                = "thirdrail-fd-${local.environment}"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.common_tags
}

resource "azurerm_cdn_frontdoor_origin_group" "thirdrail_origin_group" {
  name                     = "thirdrail-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.thirdrail_frontdoor.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "thirdrail_origin" {
  name                          = "staticwebapp"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.thirdrail_origin_group.id

  enabled                        = true
  host_name                      = azurerm_static_web_app.thirdrail_portal.default_host_name
  origin_host_header             = azurerm_static_web_app.thirdrail_portal.default_host_name
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_endpoint" "thirdrail_endpoint" {
  name                     = "thirdrail-preorder-${local.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.thirdrail_frontdoor.id
}

resource "azurerm_cdn_frontdoor_route" "thirdrail_route" {
  name                          = "thirdrail-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.thirdrail_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.thirdrail_origin_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.thirdrail_origin.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true

  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.paymentportal.id]
}

resource "azurerm_cdn_frontdoor_custom_domain" "paymentportal" {
  name                     = "paymentportal"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.thirdrail_frontdoor.id
  host_name                = "paymentportal.thirdandtownsendmodels.com"

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "paymentportal_assoc" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.paymentportal.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.thirdrail_route.id]
}

# API Backend - Origin Group for App Service
resource "azurerm_cdn_frontdoor_origin_group" "api_origin_group" {
  name                     = "thirdrail-api-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.thirdrail_frontdoor.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/health"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "api_origin" {
  name                          = "appservice"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api_origin_group.id

  enabled                        = true
  host_name                      = azurerm_linux_web_app.thirdrail-service-app.default_hostname
  origin_host_header             = azurerm_linux_web_app.thirdrail-service-app.default_hostname
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_custom_domain" "api_domain" {
  name                     = "api-paymentportal"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.thirdrail_frontdoor.id
  host_name                = "api.paymentportal.thirdandtownsendmodels.com"

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_route" "api_route" {
  name                          = "thirdrail-api-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.thirdrail_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api_origin_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.api_origin.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = false
  https_redirect_enabled = true

  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.api_domain.id]
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "api_assoc" {
  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.api_domain.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.api_route.id]
}


