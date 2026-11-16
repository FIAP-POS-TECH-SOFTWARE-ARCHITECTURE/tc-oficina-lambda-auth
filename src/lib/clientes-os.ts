import { getParametro } from "./ssm";

export interface ClienteOs {
  id: string;
  nome: string;
  ativo: boolean;
}

export class ErroConsultaCliente extends Error {
  constructor(motivo: string, opcoes?: { cause?: unknown }) {
    super(motivo, opcoes);
    this.name = "ErroConsultaCliente";
  }
}

export const TIMEOUT_PADRAO_MS = 3000;

function urlBaseOs(): string {
  const url = process.env.OS_SERVICE_URL;
  if (!url) throw new ErroConsultaCliente("OS_SERVICE_URL não configurada");
  return url.replace(/\/+$/, "");
}

// O contrato define { id, nome, ativo }; o os-service pode devolver o mesmo objeto
// dentro do envelope padrão de resposta ({ status, success, data }).
function extrairCliente(corpo: unknown): ClienteOs | null {
  const candidato =
    corpo !== null && typeof corpo === "object" && "data" in corpo
      ? (corpo as { data: unknown }).data
      : corpo;
  if (candidato === null || typeof candidato !== "object") return null;

  const { id, nome, ativo } = candidato as Record<string, unknown>;
  if (typeof id !== "string" || typeof nome !== "string" || typeof ativo !== "boolean") return null;
  return { id, nome, ativo };
}

export async function buscarClientePorCpf(
  cpf: string,
  timeoutMs: number = TIMEOUT_PADRAO_MS,
): Promise<ClienteOs | null> {
  const url = `${urlBaseOs()}/internal/clientes/por-documento/${encodeURIComponent(cpf)}`;
  const chave = await getParametro(`/oficina/${process.env.ENVIRONMENT}/internal-api-key`);

  let resposta: Response;
  try {
    resposta = await fetch(url, {
      method: "GET",
      headers: { accept: "application/json", "x-internal-api-key": chave },
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (erro) {
    // DOMException de timeout não passa em instanceof entre realms; compara pelo nome.
    const motivo = (erro as Error).name === "TimeoutError" ? `timeout após ${timeoutMs}ms` : "falha de rede";
    throw new ErroConsultaCliente(motivo, { cause: erro });
  }

  if (resposta.status === 404) return null;
  if (!resposta.ok) throw new ErroConsultaCliente(`os-service respondeu ${resposta.status}`);

  let corpo: unknown;
  try {
    corpo = await resposta.json();
  } catch (erro) {
    throw new ErroConsultaCliente("resposta do os-service não é JSON válido", { cause: erro });
  }

  const cliente = extrairCliente(corpo);
  if (!cliente) throw new ErroConsultaCliente("resposta do os-service fora do contrato");
  return cliente;
}
