data "aws_iam_role" "lab_role" { name = "LabRole" }

data "aws_ssm_parameter" "app_lb_hostname" {
  name = "/${var.project_name}/${var.environment}/app-lb-hostname"
}

locals {
  app_base_url = "http://${data.aws_ssm_parameter.app_lb_hostname.value}"
}
