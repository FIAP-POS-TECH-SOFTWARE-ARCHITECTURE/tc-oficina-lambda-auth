jest.mock("../src/lib/ssm");

import { buscarClientePorCpf, ErroConsultaCliente, TIMEOUT_PADRAO_MS } from "../src/lib/clientes-os";
import { getParametro } from "../src/lib/ssm";

const mockParametro = getParametro as jest.MockedFunction<typeof getParametro>;
let fetchMock: jest.SpiedFunction<typeof fetch>;

const json = (status: number, corpo: unknown) =>
  new Response(JSON.stringify(corpo), { status, headers: { "content-type": "application/json" } });

const CPF = "52998224725";

beforeEach(() => {
  jest.resetAllMocks();
  process.env.ENVIRONMENT = "homolog";
  process.env.OS_SERVICE_URL = "http://os.elb.test";
  mockParametro.mockResolvedValue("chave-interna-teste");
  fetchMock = jest.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

describe("buscarClientePorCpf", () => {
  it("chama o endpoint interno do os-service com a API key do SSM e timeout", async () => {
    fetchMock.mockResolvedValue(json(200, { id: "c1", nome: "Maria", ativo: true }));

    await buscarClientePorCpf(CPF);

    expect(mockParametro).toHaveBeenCalledWith("/oficina/homolog/internal-api-key");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(`http://os.elb.test/internal/clientes/por-documento/${CPF}`);
    expect(init?.method).toBe("GET");
    expect((init?.headers as Record<string, string>)["x-internal-api-key"]).toBe("chave-interna-teste");
    expect(init?.signal).toBeInstanceOf(AbortSignal);
  });

  it("ignora barra final em OS_SERVICE_URL", async () => {
    process.env.OS_SERVICE_URL = "http://os.elb.test/";
    fetchMock.mockResolvedValue(json(200, { id: "c1", nome: "Maria", ativo: true }));

    await buscarClientePorCpf(CPF);

    expect(fetchMock.mock.calls[0][0]).toBe(`http://os.elb.test/internal/clientes/por-documento/${CPF}`);
  });

  it.each([true, false])("aceita corpo do contrato (ativo=%s)", async (ativo) => {
    fetchMock.mockResolvedValue(json(200, { id: "c1", nome: "Maria", ativo }));
    await expect(buscarClientePorCpf(CPF)).resolves.toEqual({ id: "c1", nome: "Maria", ativo });
  });

  it("aceita o envelope padrão de resposta do os-service", async () => {
    fetchMock.mockResolvedValue(
      json(200, { status: 200, success: true, data: { id: "c1", nome: "Maria", ativo: true } }),
    );
    await expect(buscarClientePorCpf(CPF)).resolves.toEqual({ id: "c1", nome: "Maria", ativo: true });
  });

  it("devolve null quando o os-service responde 404", async () => {
    fetchMock.mockResolvedValue(json(404, { statusCode: 404, message: "Cliente não encontrado" }));
    await expect(buscarClientePorCpf(CPF)).resolves.toBeNull();
  });

  it.each([401, 403, 500, 502, 503])("falha com ErroConsultaCliente quando o os-service responde %i", async (status) => {
    fetchMock.mockResolvedValue(json(status, { statusCode: status }));
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow(new ErroConsultaCliente(`os-service respondeu ${status}`));
  });

  it("falha por timeout", async () => {
    fetchMock.mockImplementation(
      (_url, init) =>
        new Promise<Response>((_resolve, reject) => {
          const sinal = init!.signal!;
          sinal.addEventListener("abort", () => reject(sinal.reason));
        }),
    );
    await expect(buscarClientePorCpf(CPF, 20)).rejects.toThrow("timeout após 20ms");
  });

  it("usa 3 segundos de timeout por padrão", () => {
    expect(TIMEOUT_PADRAO_MS).toBe(3000);
  });

  it("falha por erro de rede", async () => {
    fetchMock.mockRejectedValue(new TypeError("fetch failed"));
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow("falha de rede");
  });

  it("falha quando o corpo não é JSON", async () => {
    fetchMock.mockResolvedValue(new Response("<html>erro</html>", { status: 200 }));
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow("não é JSON válido");
  });

  it.each([
    [{ id: 1, nome: "Maria", ativo: true }],
    [{ id: "c1", nome: null, ativo: true }],
    [{ id: "c1", nome: "Maria", ativo: "sim" }],
    ["texto"],
    [null],
  ])("rejeita corpo fora do contrato %j", async (corpo) => {
    fetchMock.mockResolvedValue(json(200, corpo));
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow("fora do contrato");
  });

  it("falha sem OS_SERVICE_URL e não chama a rede", async () => {
    delete process.env.OS_SERVICE_URL;
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow("OS_SERVICE_URL não configurada");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockParametro).not.toHaveBeenCalled();
  });

  it("propaga falha do SSM", async () => {
    mockParametro.mockRejectedValue(new Error("Parâmetro SSM ausente"));
    await expect(buscarClientePorCpf(CPF)).rejects.toThrow("Parâmetro SSM ausente");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
