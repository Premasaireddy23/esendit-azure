variable "subscription_id_prod" {
  type        = string
  description = "Prod subscription ID"
}

variable "subscription_id_dev" {
  type        = string
  description = "Dev subscription ID"
}

variable "budget_alert_emails" {
  type        = list(string)
  description = "Emails to receive budget alerts"
  default     = []
}

variable "budget_amount_prod" {
  type        = number
  description = "Monthly budget for Prod subscription"
  default     = 500
}

variable "budget_amount_dev" {
  type        = number
  description = "Monthly budget for Dev subscription"
  default     = 150
}

variable "allowed_locations" {
  type        = list(string)
  description = "Azure allowed regions (use location codes)"
  # westindia + centralindia (DR) as you decided
  default = ["westindia", "centralindia"]
}
