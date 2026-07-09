const prisma = require('../utils/prisma');

function _serializarFaixa(f) {
  return {
    id:          f.id,
    ordem:       f.ordem,
    valorMin:    Number(f.valorMin),
    valorMax:    f.valorMax != null ? Number(f.valorMax) : null,
    percentual:  Number(f.percentual),
    criadoEm:    f.criadoEm,
    atualizadoEm: f.atualizadoEm,
  };
}

async function listarFaixas() {
  const faixas = await prisma.markupFaixa.findMany({ orderBy: { ordem: 'asc' } });
  return faixas.map(_serializarFaixa);
}

async function salvarFaixas(faixas = []) {
  for (const f of faixas) {
    if (f.valorMin == null || f.percentual == null) {
      throw { status: 400, message: 'Cada faixa precisa de valorMin e percentual.' };
    }
    if (f.valorMax != null && Number(f.valorMax) <= Number(f.valorMin)) {
      throw { status: 400, message: `valorMax deve ser maior que valorMin (faixa com min=${f.valorMin}).` };
    }
    if (Number(f.percentual) < 0) {
      throw { status: 400, message: 'O percentual não pode ser negativo.' };
    }
  }

  for (let i = 0; i < faixas.length - 1; i++) {
    if (faixas[i].valorMax == null) {
      throw { status: 400, message: 'Somente a última faixa pode ter valorMax em aberto.' };
    }
  }

  await prisma.$transaction([
    prisma.markupFaixa.deleteMany(),
    ...faixas.map((f, idx) =>
      prisma.markupFaixa.create({
        data: {
          ordem:      idx + 1,
          valorMin:   Number(f.valorMin),
          valorMax:   f.valorMax != null ? Number(f.valorMax) : null,
          percentual: Number(f.percentual),
        },
      })
    ),
  ]);

  return listarFaixas();
}

async function percentualMarkupPara(valorBase) {
  const faixas = await listarFaixas();
  if (!faixas.length) return null;

  for (const f of faixas) {
    const acimaDaMin = Number(valorBase) >= f.valorMin;
    const abaixoDaMax = f.valorMax == null || Number(valorBase) <= f.valorMax;
    if (acimaDaMin && abaixoDaMax) return f.percentual;
  }

  return faixas[faixas.length - 1].percentual;
}

async function listarConfiguracoes() {
  const configs = await prisma.configuracaoSistema.findMany();
  return Object.fromEntries(configs.map((c) => [c.chave, c.valor]));
}

async function obterConfiguracao(chave) {
  const c = await prisma.configuracaoSistema.findUnique({ where: { chave } });
  return c ? c.valor : null;
}

async function salvarConfiguracao(chave, valor) {
  await prisma.configuracaoSistema.upsert({
    where:  { chave },
    update: { valor: String(valor) },
    create: { chave, valor: String(valor) },
  });
  return { chave, valor: String(valor) };
}

async function salvarConfiguracoes(dados = {}) {
  const ops = Object.entries(dados).map(([chave, valor]) =>
    prisma.configuracaoSistema.upsert({
      where:  { chave },
      update: { valor: String(valor) },
      create: { chave, valor: String(valor) },
    })
  );
  await prisma.$transaction(ops);
  return listarConfiguracoes();
}

async function obterParametros(valorBase) {
  const [percentualMarkup, impostoStr] = await Promise.all([
    percentualMarkupPara(valorBase),
    obterConfiguracao('impostoSobra'),
  ]);
  return {
    percentualMarkup: percentualMarkup ?? 0,
    impostoSobra:     impostoStr != null ? Number(impostoStr) : 0,
  };
}

module.exports = {
  listarFaixas,
  salvarFaixas,
  percentualMarkupPara,
  listarConfiguracoes,
  obterConfiguracao,
  salvarConfiguracao,
  salvarConfiguracoes,
  obterParametros,
};