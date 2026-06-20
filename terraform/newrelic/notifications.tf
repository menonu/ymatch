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
  account_id     = var.account_id
  name           = "ymatch Discord Channel"
  type           = "WEBHOOK"
  destination_id = newrelic_notification_destination.discord.id
  product        = "IINT"

  property {
    # Discord webhook payload. The `content` string is templated by New
    # Relic's workflow engine (Handlebars) at send time. The previous
    # template used {{ policyName }} / {{ conditionName }} / {{ details }},
    # which are NOT valid workflow variables — they rendered as "N/A"
    # (#160, #285). Replaced with the documented workflow variables:
    #   {{issueTitle}}                          — issue title (summary)
    #   {{accumulations.conditionName/policyName}} — breached condition /
    #                                               policy (lists, #each)
    #   {{state}} / {{priority}}               — ACTIVATED/CLOSED, CRITICAL/…
    #   {{issuePageUrl}}                        — deep link to the issue
    # See https://docs.newrelic.com/docs/alerts/get-notified/custom-variables-alert-event-workflows/
    key = "payload"
    value = jsonencode({
      content = join("\n", [
        "🚨 **New Relic Alert**",
        "**Issue:** {{issueTitle}}",
        "**Condition:** {{#each accumulations.conditionName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}",
        "**Policy:** {{#each accumulations.policyName}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}",
        "**State:** {{state}}",
        "**Priority:** {{priority}}",
        "**Open:** {{issuePageUrl}}",
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
