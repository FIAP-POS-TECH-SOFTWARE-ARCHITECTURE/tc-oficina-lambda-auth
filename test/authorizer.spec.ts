import jwt from "jsonwebtoken";

jest.mock("../src/lib/ssm");

import { handler } from "../src/handlers/authorizer";
import { getParametro } from "../src/lib/ssm";

const mockParametro = getParametro as jest.MockedFunction<typeof getParametro>;
const SEGREDO = "segredo-de-teste";

const evento = (authorization?: string) =>
  ({ headers: authorization ? { authorization } : {} }) as never;

beforeEach(() => {
  jest.resetAllMocks();
  mockParametro.mockResolvedValue(SEGREDO);
  process.env.ENVIRONMENT = "homolog";
});

describe("authorizer", () => {
  it("nega sem header Authorization", async () => {
    expect((await handler(evento())).isAuthorized).toBe(false);
  });

  it("nega token inválido", async () => {
    expect((await handler(evento("Bearer lixo"))).isAuthorized).toBe(false);
  });

  it("nega token de usuário interno (type ausente)", async () => {
    const token = jwt.sign({ sub: "u1", role: "ADMINISTRADOR" }, SEGREDO);
    expect((await handler(evento(`Bearer ${token}`))).isAuthorized).toBe(false);
  });

  it("autoriza token de cliente e propaga clienteId", async () => {
    const token = jwt.sign({ sub: "c1", type: "cliente" }, SEGREDO);
    const res = await handler(evento(`Bearer ${token}`));
    expect(res.isAuthorized).toBe(true);
    expect(res.context).toEqual({ clienteId: "c1" });
  });
});
