locals {
  environment = "prod"
  project     = "thirdrail"
  location    = "eastus"

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
  sku_name            = "B1"
}

resource "azurerm_storage_account" "thirdrail_resources_sa" {
  name                     = "thirdrail${local.environment}resources"
  resource_group_name      = azurerm_resource_group.thirdrail_rg.name
  location                 = azurerm_resource_group.thirdrail_rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_account_static_website" "thirdrail_resources_sa_website" {
  storage_account_id = azurerm_storage_account.thirdrail_resources_sa.id
  error_404_document = "index.html"
  index_document     = "index.html"
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
    location          = "eastus"
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
  name                        = "thirdrail-vault-${local.environment}"
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

resource "azurerm_key_vault_secret" "azure-blob-key" {
  name         = "AZURE-STORAGE-KEY"
  value        = azurerm_storage_account.thirdrail_resources_sa.primary_access_key
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_secret" "azure-blob-name" {
  name         = "AZURE-STORAGE-NAME"
  value        = azurerm_storage_account.thirdrail_resources_sa.name
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_secret" "azure-blob-endpoint" {
  name         = "AZURE-BLOB-ENDPOINT"
  value        = azurerm_storage_account.thirdrail_resources_sa.primary_blob_endpoint
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_secret" "azure-staticsite-endpoint" {
  name         = "STATIC-WEBSITE-BASE-URL"
  value        = azurerm_storage_account.thirdrail_resources_sa.primary_web_endpoint
  key_vault_id = "${azurerm_key_vault.vault.id}"
    depends_on = [
    azurerm_key_vault_access_policy.terraform-access-policy
  ]
}

resource "azurerm_key_vault_secret" "WIX-api-key" {
  name         = "WIX-API-KEY"
  value        = "IST.eyJraWQiOiJQb3pIX2FDMiIsImFsZyI6IlJTMjU2In0.eyJkYXRhIjoie1wiaWRcIjpcIjhlMDMzZGE2LWMyYmMtNDI5NS05ODQ5LWVjNjc2NTg1MGQ0ZFwiLFwiaWRlbnRpdHlcIjp7XCJ0eXBlXCI6XCJhcHBsaWNhdGlvblwiLFwiaWRcIjpcImY4YmM4YmM1LTc4NTQtNGRjYy04Y2UyLTNlYTZjNGY3OTczMFwifSxcInRlbmFudFwiOntcInR5cGVcIjpcImFjY291bnRcIixcImlkXCI6XCI1NTk0ZTQ3Zi00MzNhLTRkNjgtOTE3YS1iNzE5ZTU2MWRiMDFcIn19IiwiaWF0IjoxNzY2OTM5ODIwfQ.WTvlceICU0CQfSMrEd9P8KWIHIWtAW2sMs5TwZI9WuYs9e9p6msAgyCXPsxcw2fR4E1Yw3GlkP007mKOk4acgjzyK0WQ9awzlDwhQbfI6EdzcboAIjlljfu9eBWkPP-CZTBpvFTnl8cnkpqvBpt8g-wsmD7KDE_eqcVrrVBNbDJEyEf8Cv2-FTjh-HwahTqcRnngcOw6WRCp0uoNPCbIiqXSZhqRCA6ljp87EIUrySheza4SINi8cz2rttObPL1NbilwCLjuHqeBlfzHRkDHNqd9f8ygu-0myOw5hVt4-0QJtp8DSmq9RlGDCTEJkg5DZ66MVCDS0jPMIMRwFztNJw"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

resource "azurerm_key_vault_secret" "WIX-site-id" {
  name         = "WIX-SITE-ID"
  value        = "49bd8033-547b-411e-81e5-644d8a2b4692"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-api-login-id" {
  name         = "AUTHORIZENET-API-LOGIN-ID"
  value        = "7SL5ke25"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-transaction-key" {
  name         = "AUTHORIZENET-TRANSACTION-KEY"
  value        = "9Q942kX5dwU3y353"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-environment" {
  name         = "AUTHORIZENET-ENVIRONMENT"
  value        = "sandbox"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

resource "azurerm_key_vault_secret" "AUTHORIZENET-client-key" {
  name         = "AUTHORIZENET-CLIENT-KEY"
  value        = "5Wjac683WVdza2DGzxHu68jDP37ERGYz98wPVUKhvtM6e438MapP9L6zFZgwNk3F"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}



resource "azurerm_key_vault_secret" "paypal-client-id-secret" {
  name         = "PAYPAL-CLIENT-ID"
  value        = "AZTzsoATQwMulUG6Lsga62w0c3J6KOdogGKqO-IIlG3MByxtMO2pj6r_7N5a2YHMRyEPnzloWdATG0E-"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}



resource "azurerm_key_vault_secret" "paypal-client-secret" {
  name         = "PAYPAL-CLIENT-SECRET"
  value        = "EGJYNyA9ZXnVJ0ahpcoviGXkm3kwOJiKbVgDAI4DpHMRnH5d_92U9bW8YHEfn0ciwWqZdLs9eDs1MpAM"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}



resource "azurerm_key_vault_secret" "paypal-environment-secret" {
  name         = "PAYPAL-ENVIRONMENT"
  value        = "sandbox"
  key_vault_id = "${azurerm_key_vault.vault.id}"
}

# Azure CDN for custom domain on static website
resource "azurerm_cdn_profile" "thirdrail_cdn" {
  name                = "thirdrail-cdn-${local.environment}"
  location            = "global"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name
  sku                 = "Standard_Microsoft"
  tags                = local.common_tags
}

resource "azurerm_cdn_endpoint" "thirdrail_cdn_endpoint" {
  name                = "thirdrail-preorder-${local.environment}"
  profile_name        = azurerm_cdn_profile.thirdrail_cdn.name
  location            = "global"
  resource_group_name = azurerm_resource_group.thirdrail_rg.name

  origin_host_header = azurerm_storage_account.thirdrail_resources_sa.primary_web_host

  origin {
    name      = "storagestaticwebsite"
    host_name = azurerm_storage_account.thirdrail_resources_sa.primary_web_host
  }

  delivery_rule {
    name  = "EnforceHTTPS"
    order = 1

    request_scheme_condition {
      operator     = "Equal"
      match_values = ["HTTP"]
    }

    url_redirect_action {
      redirect_type = "Found"
      protocol      = "Https"
    }
  }

  delivery_rule {
    name  = "SPARewrite"
    order = 2

    url_file_extension_condition {
      operator     = "LessThan"
      match_values = ["1"]
    }

    url_rewrite_action {
      source_pattern          = "/"
      destination             = "/index.html"
      preserve_unmatched_path = false
    }
  }
}

resource "azurerm_cdn_endpoint_custom_domain" "preorder_domain" {
  name            = "paymentportal"
  cdn_endpoint_id = azurerm_cdn_endpoint.thirdrail_cdn_endpoint.id
  host_name       = "paymentportal.thirdandtownsendmodels.com"

  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
  }
}


