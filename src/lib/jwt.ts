import jwt from "jsonwebtoken";

const EXPIRACAO_SEGUNDOS = 3600;

export function assinarTokenCliente(
  cliente: { id: string; nome: string },
  cpf: string,
  segredo: string,
): string {
  return jwt.sign(
    { sub: cliente.id, nome: cliente.nome, cpf, type: "cliente" },
    segredo,
    { algorithm: "HS256", expiresIn: EXPIRACAO_SEGUNDOS },
  );
}

export function verificarTokenCliente(
  token: string,
  segredo: string,
): { sub: string; type: string } | null {
  try {
    const payload = jwt.verify(token, segredo, { algorithms: ["HS256"] });
    if (typeof payload === "string") return null;
    if (payload.type !== "cliente" || typeof payload.sub !== "string") return null;
    return { sub: payload.sub, type: payload.type };
  } catch {
    return null;
  }
}

export const EXPIRES_IN = EXPIRACAO_SEGUNDOS;
