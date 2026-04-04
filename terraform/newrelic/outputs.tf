output "api_monitor_id" {
  description = "GUID of the API synthetic monitor"
  value       = newrelic_synthetics_monitor.api_health.id
}

output "frontend_monitor_id" {
  description = "GUID of the frontend synthetic monitor"
  value       = newrelic_synthetics_monitor.frontend.id
}

output "alert_policy_id" {
  description = "ID of the alert policy"
  value       = newrelic_alert_policy.oci_production.id
}

output "dashboard_guid" {
  description = "GUID of the production dashboard"
  value       = newrelic_one_dashboard.production.guid
}

output "dashboard_url" {
  description = "URL to the production dashboard"
  value       = "https://one.newrelic.com/dashboards/${newrelic_one_dashboard.production.guid}"
}
