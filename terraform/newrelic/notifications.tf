# ---------------------------------------------------
# Discord Webhook Notification
# ---------------------------------------------------
resource "newrelic_notification_destination" "discord" {
  account_id = var.account_id
  name       = "ymatch Discord Alerts"
  type       = "WEBHOOK"

  property {
    key   = "url"
    value = var.discord_webhook_url
  }
}

resource "newrelic_notification_channel" "discord" {
  account_id    = var.account_id
  name          = "ymatch Discord Channel"
  type          = "WEBHOOK"
  destination_id = newrelic_notification_destination.discord.id
  product       = "IINT"

  property {
    key   = "payload"
    value = jsonencode({
      content = join("\n", [
        "🚨 **New Relic Alert**",
        "**Policy:** {{ policyName }}",
        "**Condition:** {{ conditionName }}",
        "**Details:** {{ details }}",
        "**State:** {{ state }}",
      ])
    })
    label = "Webhook Payload"
  }
}

# ---------------------------------------------------
# Workflow: Alert Policy → Discord
# ---------------------------------------------------
resource "newrelic_workflow" "discord_alerts" {
  name                  = "ymatch Discord Notifications"
  muting_rules_handling = "DONT_NOTIFY_FULLY_MUTED_ISSUES"

  issues_filter {
    name = "ymatch-policy-filter"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.oci_production.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.discord.id
  }
}
