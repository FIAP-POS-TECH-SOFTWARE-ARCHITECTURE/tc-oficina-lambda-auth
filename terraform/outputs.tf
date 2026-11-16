output "api_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "os_service_url" {
  description = "URL base do os-service usada pelo gateway e pela Lambda token"
  value       = nonsensitive(local.base_urls["os-service"])
}

output "servicos_roteados" {
  description = "Serviços com rotas no gateway neste apply"
  value       = sort(tolist(local.servicos_roteados))
}
