import { cpfValido, normalizarCpf } from "../src/lib/cpf";

describe("normalizarCpf", () => {
  it("remove máscara", () => {
    expect(normalizarCpf("123.456.789-09")).toBe("12345678909");
  });
});

describe("cpfValido", () => {
  it.each(["12345678909", "52998224725"])("aceita CPF válido %s", (cpf) => {
    expect(cpfValido(cpf)).toBe(true);
  });

  it.each([
    "12345678900",   // dígito verificador errado
    "11111111111",   // todos iguais
    "123",           // curto
    "1234567890123", // longo
    "",              // vazio
    "abcdefghijk",   // não numérico
  ])("rejeita %s", (cpf) => {
    expect(cpfValido(cpf)).toBe(false);
  });
});
