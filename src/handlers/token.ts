import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import { cpfValido, normalizarCpf } from "../lib/cpf";
import { buscarClientePorCpf } from "../lib/db";
import { assinarTokenCliente, EXPIRES_IN } from "../lib/jwt";
import { getParametro } from "../lib/ssm";

const resposta = (
  statusCode: number,
  body: Record<string, unknown>,
): APIGatewayProxyStructuredResultV2 => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export async function handler(
  event: APIGatewayProxyEventV2,
): Promise<APIGatewayProxyStructuredResultV2> {
  let cpfEntrada: string | undefined;
  try {
    cpfEntrada = JSON.parse(event.body ?? "{}").cpf;
  } catch {
    return resposta(400, { message: "Body inválido: esperado JSON com campo cpf" });
  }

  const cpf = normalizarCpf(cpfEntrada ?? "");
  if (!cpfValido(cpf)) {
    return resposta(400, { message: "CPF inválido" });
  }

  const cliente = await buscarClientePorCpf(cpf);
  if (!cliente || !cliente.ativo) {
    // 401 genérico: não revelar se o CPF existe na base.
    console.log(JSON.stringify({ event: "auth.denied", motivo: cliente ? "inativo" : "inexistente" }));
    return resposta(401, { message: "Não autorizado" });
  }

  const segredo = await getParametro(`/oficina/${process.env.ENVIRONMENT}/jwt-secret`);
  const token = assinarTokenCliente(cliente, cpf, segredo);

  console.log(JSON.stringify({ event: "auth.granted", clienteId: cliente.id }));
  return resposta(200, { token, expiresIn: EXPIRES_IN });
}
