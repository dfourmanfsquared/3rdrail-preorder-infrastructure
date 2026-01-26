output "frontdoor_endpoint_hostname" {
  description = "Front Door endpoint hostname for DNS CNAME record"
  value       = azurerm_cdn_frontdoor_endpoint.thirdrail_endpoint.host_name
}

output "static_website_url" {
  description = "Static website URL (direct storage access)"
  value       = azurerm_storage_account.thirdrail_resources_sa.primary_web_endpoint
}

output "custom_domain_url" {
  description = "Custom domain URL for the payment portal"
  value       = "https://paymentportal.thirdandtownsendmodels.com"
}

output "custom_domain_validation_token" {
  description = "TXT record value for domain validation"
  value       = azurerm_cdn_frontdoor_custom_domain.paymentportal.validation_token
}
