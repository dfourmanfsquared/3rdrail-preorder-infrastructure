locals {
  environment = "dev"
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
  error_404_document = "custom_not_found.html"
  index_document     = "custom_index.html"
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

resource "azurerm_cosmosdb_sql_container" "thirdrail-cosmos-sql-db-container" {
  name                  = "orders"
  resource_group_name   = azurerm_resource_group.thirdrail_rg.name
  account_name          = azurerm_cosmosdb_account.cosmosaccount.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos-sql-db.name
  partition_key_paths   = ["/email"]
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"
    included_path {
      path = "/*"
    }
  }
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
      java_server_version = "17" 
      java_version        = "17" 
    }
    health_check_path = "/health"
    health_check_eviction_time_in_min = 5
  }

app_settings ={

    "AZURE-VAULT-URI" = azurerm_key_vault.vault.vault_uri
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
    object_id = "cf2c9115-40a3-4675-b53a-74b701ef7db1"

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