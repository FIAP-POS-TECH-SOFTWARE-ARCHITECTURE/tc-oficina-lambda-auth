variable "environment" {
  type = string
  validation {
    condition     = contains(["homolog", "prod"], var.environment)
    error_message = "environment deve ser homolog ou prod."
  }
}

variable "project_name" {
  type    = string
  default = "oficina"
}
