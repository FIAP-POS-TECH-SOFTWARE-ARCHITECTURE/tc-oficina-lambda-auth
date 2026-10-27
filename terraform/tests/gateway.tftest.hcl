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

  assert {
    condition     = toset(keys(aws_apigatewayv2_route.cliente)) == toset(["GET /os/acompanhamento/{numero}"])
    error_message = "Sem billing publicado, a única rota de cliente é o acompanhamento da OS (rotas antigas de orçamento do OS removidas)."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.servico_proxy) == 0 && length(aws_apigatewayv2_route.webhook_mercado_pago) == 0
    error_message = "Rotas de billing/execution não podem existir sem hostname publicado."
  }

  assert {
    condition     = aws_apigatewayv2_route.proxy.route_key == "ANY /{proxy+}"
    error_message = "Catch-all deve continuar indo para o os-service."
  }

  assert {
    condition     = aws_apigatewayv2_route.interno_bloqueado.route_key == "ANY /internal/{proxy+}" && aws_apigatewayv2_route.interno_bloqueado.authorization_type == "AWS_IAM"
    error_message = "/internal deve ser negado no gateway (AWS_IAM)."
  }
}

run "somente_billing_publicado" {
  expect_failures = [check.hostnames_dos_servicos]

  override_data {
    target = data.aws_ssm_parameters_by_path.ambiente
    values = {
      names = ["/oficina/homolog/os-service-lb-hostname", "/oficina/homolog/billing-service-lb-hostname"]
    }
  }

  assert {
    condition     = toset(keys(aws_apigatewayv2_route.servico_proxy)) == toset(["ANY /billing/{proxy+}"])
    error_message = "Só o proxy do billing deve existir quando só ele publicou hostname."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.webhook_mercado_pago) == 1
    error_message = "Webhook do Mercado Pago deve existir quando o billing está publicado."
  }

  assert {
    condition     = toset(output.servicos_roteados) == toset(["os-service", "billing-service"])
    error_message = "servicos_roteados deve listar os-service e billing-service."
  }
}

run "todos_os_servicos_publicados" {
  override_data {
    target = data.aws_ssm_parameters_by_path.ambiente
    values = {
      names = [
        "/oficina/homolog/os-service-lb-hostname",
        "/oficina/homolog/billing-service-lb-hostname",
        "/oficina/homolog/execution-service-lb-hostname",
      ]
    }
  }

  assert {
    condition = toset(keys(aws_apigatewayv2_route.cliente)) == toset([
      "GET /os/acompanhamento/{numero}",
      "GET /billing/cliente/orcamentos/{numeroOs}",
      "POST /billing/cliente/orcamentos/{numeroOs}/aprovar",
      "POST /billing/cliente/orcamentos/{numeroOs}/rejeitar",
    ])
    error_message = "Rotas de cliente devem ser o acompanhamento da OS e as 3 rotas de orçamento do billing."
  }

  assert {
    condition     = alltrue([for rota in aws_apigatewayv2_route.cliente : rota.authorization_type == "CUSTOM"])
    error_message = "Toda rota de cliente usa o authorizer cliente-jwt."
  }

  assert {
    condition     = alltrue([for chave, integracao in aws_apigatewayv2_integration.cliente : endswith(integracao.integration_uri, split(" ", chave)[1])])
    error_message = "Integrações de cliente repassam o mesmo path da rota."
  }

  assert {
    condition     = aws_apigatewayv2_integration.cliente["POST /billing/cliente/orcamentos/{numeroOs}/aprovar"].integration_uri == "http://servico.elb.test/billing/cliente/orcamentos/{numeroOs}/aprovar"
    error_message = "Aprovação de orçamento vai para o billing-service."
  }

  assert {
    condition     = aws_apigatewayv2_integration.cliente["GET /os/acompanhamento/{numero}"].integration_uri == "http://os.elb.test/os/acompanhamento/{numero}"
    error_message = "Acompanhamento continua no os-service."
  }

  assert {
    condition     = toset(keys(aws_apigatewayv2_route.servico_proxy)) == toset(["ANY /billing/{proxy+}", "ANY /execucao/{proxy+}"])
    error_message = "Proxies de billing e execution devem existir."
  }

  assert {
    condition     = alltrue([for rota in aws_apigatewayv2_route.servico_proxy : rota.authorization_type == "NONE"])
    error_message = "Proxies de billing/execution não usam authorizer de cliente (o serviço valida o JWT de staff)."
  }

  assert {
    condition     = aws_apigatewayv2_integration.servico_proxy["ANY /execucao/{proxy+}"].integration_uri == "http://servico.elb.test/execucao/{proxy}"
    error_message = "Proxy de execution repassa /execucao/{proxy}."
  }

  assert {
    condition     = aws_apigatewayv2_route.webhook_mercado_pago[0].route_key == "POST /billing/webhooks/mercado-pago" && aws_apigatewayv2_route.webhook_mercado_pago[0].authorization_type == "NONE"
    error_message = "Webhook do Mercado Pago é rota explícita e pública."
  }

  assert {
    condition     = try(aws_apigatewayv2_integration.webhook_mercado_pago[0].request_parameters["append:header.x-request-id"], null) == null
    error_message = "Webhook não pode anexar x-request-id: o header do Mercado Pago faz parte da assinatura."
  }

  assert {
    condition = alltrue([
      for integracao in concat(
        values(aws_apigatewayv2_integration.cliente),
        values(aws_apigatewayv2_integration.servico_proxy),
        [aws_apigatewayv2_integration.proxy, aws_apigatewayv2_integration.interno_bloqueado],
      ) : integracao.request_parameters["append:header.x-request-id"] == "$context.requestId"
    ])
    error_message = "Demais integrações propagam x-request-id com o requestId do gateway."
  }

  assert {
    condition     = toset(output.servicos_roteados) == toset(["os-service", "billing-service", "execution-service"])
    error_message = "servicos_roteados deve listar os 3 serviços."
  }
}
