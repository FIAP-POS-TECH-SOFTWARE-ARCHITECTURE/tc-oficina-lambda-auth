import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const client = new SSMClient({});
const cache = new Map<string, string>();

export async function getParametro(nome: string): Promise<string> {
  const cacheado = cache.get(nome);
  if (cacheado) return cacheado;

  const { Parameter } = await client.send(
    new GetParameterCommand({ Name: nome, WithDecryption: true }),
  );
  if (!Parameter?.Value) throw new Error(`Parâmetro SSM ausente: ${nome}`);
  cache.set(nome, Parameter.Value);
  return Parameter.Value;
}
