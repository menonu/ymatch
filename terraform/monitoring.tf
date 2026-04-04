# ---------------------------------------------------
# GCP Budget Alert (Free tier guard)
# ---------------------------------------------------

# Enable the Cloud Billing Budget API
resource "google_project_service" "billing_budgets" {
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

resource "google_billing_budget" "ymatch" {
  billing_account = var.billing_account
  display_name    = "ymatch-free-tier-guard"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "1"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.8
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.billing_budgets]
}
