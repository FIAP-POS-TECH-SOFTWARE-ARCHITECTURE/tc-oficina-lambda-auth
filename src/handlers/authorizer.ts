import type { APIGatewayRequestAuthorizerEventV2, APIGatewaySimpleAuthorizerWithContextResult } from "aws-lambda";
import { verificarTokenCliente } from "../lib/jwt";
import { getParametro } from "../lib/ssm";

type Resultado = APIGatewaySimpleAuthorizerWithContextResult<{ clienteId: string } | undefined>;

export async function handler(event: APIGatewayRequestAuthorizerEventV2): Promise<Resultado> {
  const auth = event.headers?.authorization ?? event.headers?.Authorization;
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : undefined;
  if (!token) return { isAuthorized: false, context: undefined };

  const segredo = await getParametro(`/oficina/${process.env.ENVIRONMENT}/jwt-secret`);
  const payload = verificarTokenCliente(token, segredo);
  if (!payload) return { isAuthorized: false, context: undefined };

  return { isAuthorized: true, context: { clienteId: payload.sub } };
}
