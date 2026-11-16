import type { APIGatewayProxyEventV2 } from "aws-lambda";
import jwt from "jsonwebtoken";

jest.mock("../src/lib/clientes-os");
jest.mock("../src/lib/ssm");

import { handler } from "../src/handlers/token";
import { buscarClientePorCpf } from "../src/lib/clientes-os";
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
    expect(mockBuscar).not.toHaveBeenCalled();
  });

  it("retorna 400 sem body", async () => {
    const res = await handler({} as APIGatewayProxyEventV2);
    expect(res.statusCode).toBe(400);
  });

  it("retorna 400 para body que não é JSON", async () => {
    const res = await handler({ body: "{cpf:" } as APIGatewayProxyEventV2);
    expect(res.statusCode).toBe(400);
  });

  it("retorna 400 para CPF não-string", async () => {
    const res = await handler(evento({ cpf: 12345678909 }));
    expect(res.statusCode).toBe(400);
  });

  it("consulta o os-service com o CPF normalizado", async () => {
    mockBuscar.mockResolvedValue(null);
    await handler(evento({ cpf: "529.982.247-25" }));
    expect(mockBuscar).toHaveBeenCalledWith("52998224725");
  });

  it("retorna 401 genérico quando cliente não existe", async () => {
    mockBuscar.mockResolvedValue(null);
    const res = await handler(evento({ cpf: "12345678909" }));
    expect(res.statusCode).toBe(401);
    expect(JSON.parse(res.body!)).toEqual({ message: "Não autorizado" });
  });

  it("retorna 401 genérico quando cliente está inativo", async () => {
    mockBuscar.mockResolvedValue({ id: "abc", nome: "Ana", ativo: false });
    const res = await handler(evento({ cpf: "12345678909" }));
    expect(res.statusCode).toBe(401);
    expect(JSON.parse(res.body!)).toEqual({ message: "Não autorizado" });
  });

  it("retorna 503 quando a consulta ao os-service falha", async () => {
    mockBuscar.mockRejectedValue(new Error("os-service respondeu 500"));
    const res = await handler(evento({ cpf: "12345678909" }));
    expect(res.statusCode).toBe(503);
    expect(JSON.parse(res.body!)).toEqual({ message: "Serviço indisponível" });
    expect(mockParametro).not.toHaveBeenCalled();
  });

  it("retorna 200 com token de cliente para cliente ativo", async () => {
    mockBuscar.mockResolvedValue({ id: "abc", nome: "Ana", ativo: true });
    const res = await handler(evento({ cpf: "123.456.789-09" }));
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body!);
    expect(body.expiresIn).toBe(3600);
    expect(mockParametro).toHaveBeenCalledWith("/oficina/homolog/jwt-secret");
    const payload = jwt.verify(body.token, "segredo-de-teste") as jwt.JwtPayload;
    expect(payload).toMatchObject({ sub: "abc", nome: "Ana", cpf: "12345678909", type: "cliente" });
  });
});
