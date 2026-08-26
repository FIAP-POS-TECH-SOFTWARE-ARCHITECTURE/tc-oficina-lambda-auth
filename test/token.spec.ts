import type { APIGatewayProxyEventV2 } from "aws-lambda";

jest.mock("../src/lib/db");
jest.mock("../src/lib/ssm");

import { handler } from "../src/handlers/token";
import { buscarClientePorCpf } from "../src/lib/db";
import { getParametro } from "../src/lib/ssm";

const evento = (body: unknown): APIGatewayProxyEventV2 =>
  ({ body: JSON.stringify(body) }) as APIGatewayProxyEventV2;

const mockBuscar = buscarClientePorCpf as jest.MockedFunction<typeof buscarClientePorCpf>;
const mockParametro = getParametro as jest.MockedFunction<typeof getParametro>;

beforeEach(() => {
  jest.resetAllMocks();
  mockParametro.mockResolvedValue("segredo-de-teste");
  process.env.ENVIRONMENT = "homolog";
});

describe("POST /auth/token", () => {
  it("retorna 400 para CPF malformado", async () => {
    const res = await handler(evento({ cpf: "123" }));
    expect(res.statusCode).toBe(400);
  });

  it("retorna 400 sem body", async () => {
    const res = await handler({} as APIGatewayProxyEventV2);
    expect(res.statusCode).toBe(400);
  });

  it("retorna 401 quando cliente não existe", async () => {
    mockBuscar.mockResolvedValue(null);
    const res = await handler(evento({ cpf: "12345678909" }));
    expect(res.statusCode).toBe(401);
  });

  it("retorna 401 quando cliente está inativo", async () => {
    mockBuscar.mockResolvedValue({ id: "abc", nome: "Ana", ativo: false });
    const res = await handler(evento({ cpf: "12345678909" }));
    expect(res.statusCode).toBe(401);
  });

  it("retorna 200 com token para cliente ativo", async () => {
    mockBuscar.mockResolvedValue({ id: "abc", nome: "Ana", ativo: true });
    const res = await handler(evento({ cpf: "123.456.789-09" }));
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body!);
    expect(body.token).toEqual(expect.any(String));
    expect(body.expiresIn).toBe(3600);
  });
});
