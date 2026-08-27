import { Pool } from "pg";
import { getParametro } from "./ssm";

let pool: Pool | undefined;

async function getPool(): Promise<Pool> {
  if (!pool) {
    const databaseUrl = await getParametro(
      `/oficina/${process.env.ENVIRONMENT}/database-url`,
    );
    pool = new Pool({ connectionString: databaseUrl, max: 1 });
  }
  return pool;
}

export interface ClienteRow {
  id: string;
  nome: string;
  ativo: boolean;
}

export async function buscarClientePorCpf(cpf: string): Promise<ClienteRow | null> {
  const db = await getPool();
  const { rows } = await db.query<ClienteRow>(
    `SELECT id, nome, ativo FROM clientes
     WHERE documento = $1 AND tipo_documento = 'CPF'`,
    [cpf],
  );
  return rows[0] ?? null;
}
