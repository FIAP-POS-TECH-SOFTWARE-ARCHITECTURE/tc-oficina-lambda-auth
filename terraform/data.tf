data "aws_iam_role" "lab_role" { name = "LabRole" }

locals {
  prefixo_ssm = "/${var.project_name}/${var.environment}"
}

# Hostname do load balancer do os-service, publicado pelo CD do os-service.
# Obrigatório: é o destino do catch-all e da consulta de cliente da Lambda token.
data "aws_ssm_parameter" "os_service" {
  name = "${local.prefixo_ssm}/os-service-lb-hostname"
}

# billing-service e execution-service entram no gateway só depois que o CD de cada
# um publicar o hostname. A presença é detectada pelos nomes (não sensíveis) dos
# parâmetros do ambiente; SecureStrings não são decifrados.
data "aws_ssm_parameters_by_path" "ambiente" {
  path            = local.prefixo_ssm
  recursive       = false
  with_decryption = false
}

locals {
  servicos_opcionais = toset([
    for servico in ["billing-service", "execution-service"] : servico
    if contains(data.aws_ssm_parameters_by_path.ambiente.names, "${local.prefixo_ssm}/${servico}-lb-hostname")
  ])

  servicos_roteados = setunion(["os-service"], local.servicos_opcionais)
}

data "aws_ssm_parameter" "hostname_servico" {
  for_each = local.servicos_opcionais
  name     = "${local.prefixo_ssm}/${each.key}-lb-hostname"
}

locals {
  base_urls = merge(
    { "os-service" = "http://${data.aws_ssm_parameter.os_service.value}" },
    { for servico, parametro in data.aws_ssm_parameter.hostname_servico : servico => "http://${parametro.value}" },
  )
}

check "hostnames_dos_servicos" {
  assert {
    condition     = length(local.servicos_opcionais) == 2
    error_message = "Hostname de billing-service e/ou execution-service ainda não publicado em ${local.prefixo_ssm}: as rotas /billing e /execucao ficam fora do gateway até um novo apply depois do deploy desses serviços."
  }
}
