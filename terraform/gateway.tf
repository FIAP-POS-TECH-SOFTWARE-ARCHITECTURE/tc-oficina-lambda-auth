resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

# ---------- Authorizer (JWT HS256 -> Lambda REQUEST authorizer) ----------

resource "aws_apigatewayv2_authorizer" "cliente" {
  api_id                            = aws_apigatewayv2_api.main.id
  name                              = "cliente-jwt"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_result_ttl_in_seconds  = 300
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowApiGatewayAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*"
}

# ---------- POST /auth/token (público) ----------

resource "aws_apigatewayv2_integration" "token" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.token.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "token" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /auth/token"
  target    = "integrations/${aws_apigatewayv2_integration.token.id}"
}

resource "aws_lambda_permission" "token" {
  statement_id  = "AllowApiGatewayToken"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*"
}

locals {
  # Correlação gateway -> serviço (o serviço loga esse header como requestId)
  x_request_id = {
    "append:header.x-request-id" = "$context.requestId"
  }

  # Rotas sensíveis do cliente: route_key -> serviço de destino. O path repassado é o
  # mesmo da rota. Rotas de um serviço só existem depois que o hostname dele é publicado.
  rotas_cliente_todas = {
    "GET /os/acompanhamento/{numero}"                      = "os-service"
    "GET /billing/cliente/orcamentos/{numeroOs}"           = "billing-service"
    "POST /billing/cliente/orcamentos/{numeroOs}/aprovar"  = "billing-service"
    "POST /billing/cliente/orcamentos/{numeroOs}/rejeitar" = "billing-service"
  }

  rotas_cliente = {
    for rota, servico in local.rotas_cliente_todas : rota => servico
    if contains(local.servicos_roteados, servico)
  }

  # Proxies sem authorizer de cliente: o próprio serviço valida o JWT de staff.
  rotas_servico_todas = {
    "ANY /billing/{proxy+}"  = { servico = "billing-service", path = "/billing/{proxy}" }
    "ANY /execucao/{proxy+}" = { servico = "execution-service", path = "/execucao/{proxy}" }
  }

  rotas_servico = {
    for rota, destino in local.rotas_servico_todas : rota => destino
    if contains(local.servicos_roteados, destino.servico)
  }

  tem_billing = contains(local.servicos_roteados, "billing-service")
}

# ---------- Rotas sensíveis do cliente (proxy HTTP + authorizer) ----------

resource "aws_apigatewayv2_integration" "cliente" {
  for_each = local.rotas_cliente

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = split(" ", each.key)[0]
  integration_uri    = "${local.base_urls[each.value]}${split(" ", each.key)[1]}"
  request_parameters = local.x_request_id
}

resource "aws_apigatewayv2_route" "cliente" {
  for_each = local.rotas_cliente

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.cliente[each.key].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.cliente.id
}

# ---------- Webhook Mercado Pago (público, assinatura validada no billing) ----------

resource "aws_apigatewayv2_integration" "webhook_mercado_pago" {
  count = local.tem_billing ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = "${local.base_urls["billing-service"]}/billing/webhooks/mercado-pago"
  # Sem request_parameters: o x-request-id enviado pelo Mercado Pago faz parte do
  # manifesto assinado em x-signature; anexar o requestId do gateway invalidaria a
  # assinatura. Headers e query string do chamador são repassados como vieram.
}

resource "aws_apigatewayv2_route" "webhook_mercado_pago" {
  count = local.tem_billing ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /billing/webhooks/mercado-pago"
  target             = "integrations/${aws_apigatewayv2_integration.webhook_mercado_pago[0].id}"
  authorization_type = "NONE"
}

# ---------- Proxies de billing e execution (staff) ----------

resource "aws_apigatewayv2_integration" "servico_proxy" {
  for_each = local.rotas_servico

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.base_urls[each.value.servico]}${each.value.path}"
  request_parameters = local.x_request_id
}

resource "aws_apigatewayv2_route" "servico_proxy" {
  for_each = local.rotas_servico

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.servico_proxy[each.key].id}"
  authorization_type = "NONE"
}

# ---------- /internal bloqueado na borda ----------
# Endpoints internos são chamados direto no load balancer (Lambda token) ou pelo DNS do
# cluster; pelo gateway só passaria chamada assinada com IAM da própria conta. Sem
# assinatura o gateway responde 403. A API key interna continua como segunda barreira.

resource "aws_apigatewayv2_integration" "interno_bloqueado" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.base_urls["os-service"]}/internal/{proxy}"
  request_parameters = local.x_request_id
}

resource "aws_apigatewayv2_route" "interno_bloqueado" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /internal/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.interno_bloqueado.id}"
  authorization_type = "AWS_IAM"
}

# ---------- Catch-all: demais rotas vão direto ao os-service ----------

resource "aws_apigatewayv2_integration" "proxy" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.base_urls["os-service"]}/{proxy}"
  request_parameters = local.x_request_id
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"
}
