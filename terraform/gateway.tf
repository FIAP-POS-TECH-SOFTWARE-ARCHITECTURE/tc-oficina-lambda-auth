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

# ---------- Rotas sensíveis do cliente (proxy HTTP + authorizer) ----------

locals {
  rotas_cliente = {
    "GET /os/acompanhamento/{numero}"      = "${local.app_base_url}/os/acompanhamento/{numero}"
    "POST /os/{numero}/orcamento/aprovar"  = "${local.app_base_url}/os/{numero}/orcamento/aprovar"
    "POST /os/{numero}/orcamento/rejeitar" = "${local.app_base_url}/os/{numero}/orcamento/rejeitar"
  }
}

resource "aws_apigatewayv2_integration" "cliente" {
  for_each = local.rotas_cliente

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = split(" ", each.key)[0]
  integration_uri    = each.value

  # Correlação gateway -> app (o app loga esse header como requestId)
  request_parameters = {
    "append:header.x-request-id" = "$context.requestId"
  }
}

resource "aws_apigatewayv2_route" "cliente" {
  for_each = local.rotas_cliente

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.cliente[each.key].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.cliente.id
}

# ---------- Catch-all: demais rotas vao direto ao app ----------

resource "aws_apigatewayv2_integration" "proxy" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "${local.app_base_url}/{proxy}"

  request_parameters = {
    "append:header.x-request-id" = "$context.requestId"
  }
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"
}
