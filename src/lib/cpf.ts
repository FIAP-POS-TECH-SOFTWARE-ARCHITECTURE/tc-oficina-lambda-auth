export function normalizarCpf(entrada: string): string {
  return (entrada ?? "").replace(/\D/g, "");
}

export function cpfValido(cpf: string): boolean {
  if (!/^\d{11}$/.test(cpf)) return false;
  if (/^(\d)\1{10}$/.test(cpf)) return false;

  const digito = (base: string, pesoInicial: number): number => {
    const soma = base
      .split("")
      .reduce((acc, ch, i) => acc + Number(ch) * (pesoInicial - i), 0);
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return (
    digito(cpf.slice(0, 9), 10) === Number(cpf[9]) &&
    digito(cpf.slice(0, 10), 11) === Number(cpf[10])
  );
}
