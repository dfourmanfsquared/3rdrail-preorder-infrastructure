output "cdn_endpoint_hostname" {
  description = "CDN endpoint hostname for DNS CNAME record"
  value       = azurerm_cdn_endpoint.thirdrail_cdn_endpoint.fqdn
}

output "static_website_url" {
  description = "Static website URL (direct storage access)"
  value       = azurerm_storage_account.thirdrail_resources_sa.primary_web_endpoint
}

output "custom_domain_url" {
  description = "Custom domain URL for the payment portal"
  value       = "https://paymentportal.thirdandtownsendmodels.com"
}
