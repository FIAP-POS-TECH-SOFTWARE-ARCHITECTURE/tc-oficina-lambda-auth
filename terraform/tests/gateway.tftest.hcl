mock_provider "aws" {
  # ARN no formato real: aws_lambda_permission valida o prefixo do source_arn.
  override_resource {
    target = aws_apigatewayv2_api.main
    values = {
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:api0000001"
      api_endpoint  = "https://api0000001.execute-api.us-east-1.amazonaws.com"
    }
  }

  override_data {
    target = data.aws_iam_role.lab_role
    values = {
      arn = "arn:aws:iam::123456789012:role/LabRole"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.os_service
    values = {
      value = "os.elb.test"
    }
  }

  override_data {
    target = data.aws_ssm_parameter.hostname_servico
    values = {
      value = "servico.elb.test"
    }
  }
}

mock_provider "archive" {}

variables {
  environment = "homolog"
}

run "somente_os_service_publicado" {
  # Sem billing/execution publicados o check avisa; no apply real é só warning.
  expect_failures = [check.hostnames_dos_servicos]

  override_data {
    target = data.aws_ssm_parameters_by_path.ambiente
    values = {
      names = ["/oficina/homolog/os-service-lb-hostname", "/oficina/homolog/jwt-secret"]
    }
  }

  assert {
    condition     = aws_lambda_function.token.environment[0].variables["OS_SERVICE_URL"] == "http://os.elb.test"
    error_message = "A Lambda token deve receber a URL do os-service."
  }

  assert {
    condition     = toset(output.servicos_roteados) == toset(["os-service"])
    error_message = "Sem billing/execution publicados, só o os-service é roteado."
  }

  assert {
    condition     = output.os_service_url == "http://os.elb.test"
    error_message = "Output os_service_url deve expor a URL base do os-service."
  }
}
