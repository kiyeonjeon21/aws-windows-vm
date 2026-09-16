# Nothing in this stack was telling anyone what it cost. The in-guest watchdog
# failed silently and the instance ran for 37 hours before the bill was the
# thing that raised it. An alert is the layer that catches whatever the
# automatic stops miss, including mistakes that have nothing to do with this
# instance.
#
# Budgets alerts are free. This is an account-wide budget, not one scoped to
# this project, because a surprise is a surprise wherever it comes from.

resource "aws_budgets_budget" "monthly" {
  count = var.budget_alert_email == "" ? 0 : 1

  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_monthly_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Warn on the way up, not once the money is already spent.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Current spend rate projected to month end, which is what actually catches
  # an instance someone left running on the 3rd.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
