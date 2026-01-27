output "frontdoor_endpoint_hostname" {
  description = "Front Door endpoint hostname for DNS CNAME record"
  value       = azurerm_cdn_frontdoor_endpoint.thirdrail_endpoint.host_name
}

output "static_webapp_url" {
  description = "Static Web App URL (direct access)"
  value       = "https://${azurerm_static_web_app.thirdrail_portal.default_host_name}"
}

output "static_webapp_api_key" {
  description = "API key for deploying to Static Web App"
  value       = azurerm_static_web_app.thirdrail_portal.api_key
  sensitive   = true
}

output "custom_domain_url" {
  description = "Custom domain URL for the payment portal"
  value       = "https://paymentportal.thirdandtownsendmodels.com"
}

output "custom_domain_validation_token" {
  description = "TXT record value for domain validation"
  value       = azurerm_cdn_frontdoor_custom_domain.paymentportal.validation_token
}

output "api_domain_url" {
  description = "API custom domain URL"
  value       = "https://api.paymentportal.thirdandtownsendmodels.com"
}

output "api_domain_validation_token" {
  description = "TXT record value for API domain validation"
  value       = azurerm_cdn_frontdoor_custom_domain.api_domain.validation_token
}

output "appinsights_connection_string" {
  description = "Application Insights connection string for frontend"
  value       = azurerm_application_insights.frontend_insights.connection_string
  sensitive   = true
}

output "appinsights_instrumentation_key" {
  description = "Application Insights instrumentation key for frontend"
  value       = azurerm_application_insights.frontend_insights.instrumentation_key
  sensitive   = true
}
