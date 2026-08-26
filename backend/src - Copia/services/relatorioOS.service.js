const prisma = require('../utils/prisma');

const _includeCompleto = {
  movimentacoes: {
    include: {
      material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
      materialOrigem: { select: { id: true, nome: true } },
    },
    orderBy: { criadoEm: 'asc' },
  },
};

async function listar({ busca, cliente, materialId, materialNome, materialIdentificador, materialMedida, materialEspessura, dataInicio, dataFim } = {}) {
  const where = { status: 'FECHADA' };

  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };
  if (cliente) where.cliente = { contains: cliente, mode: 'insensitive' };

  let filtroData = null;
  if (dataInicio || dataFim) {
    filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    where.movimentacoes = where.movimentacoes
      ? { some: { ...where.movimentacoes.some, criadoEm: filtroData } }
      : { some: { criadoEm: filtroData } };
  }

  const filtroMaterial = {};
  if (materialId)            filtroMaterial.id            = Number(materialId);
  if (materialNome) {
    const tokens = materialNome.trim().split(/\s+/).filter(Boolean);
    if (tokens.length === 1) {
      filtroMaterial.nome = { contains: tokens[0], mode: 'insensitive' };
    } else {
      filtroMaterial.AND = tokens.map((t) => ({ nome: { contains: t, mode: 'insensitive' } }));
    }
  }
  if (materialIdentificador) filtroMaterial.identificador = { contains: materialIdentificador, mode: 'insensitive' };
  if (materialMedida)        filtroMaterial.medida        = { contains: materialMedida,        mode: 'insensitive' };
  if (materialEspessura)     filtroMaterial.espessura     = { contains: materialEspessura,     mode: 'insensitive' };

  if (Object.keys(filtroMaterial).length > 0) {
    where.movimentacoes = { some: { material: filtroMaterial } };
  }

  let whereMovimentacoesInclude = undefined;
  const temData     = filtroData !== null;
  const temMaterial = Object.keys(filtroMaterial).length > 0;

  if (temData && temMaterial) {
    whereMovimentacoesInclude = { criadoEm: filtroData, material: filtroMaterial };
  } else if (temData) {
    whereMovimentacoesInclude = { criadoEm: filtroData };
  } else if (temMaterial) {
    whereMovimentacoesInclude = { material: filtroMaterial };
  }

  return prisma.relacaoOS.findMany({
    where,
    include: {
      movimentacoes: {
        where: whereMovimentacoesInclude,
        include: {
          material: { select: { id: true, nome: true, unidade: true, categoria: true, identificador: true, medida: true, espessura: true } },
          materialOrigem: { select: { id: true, nome: true } },
        },
        orderBy: { criadoEm: 'desc' },
      },
    },
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorNumeroOS(numeroOS) {
  return prisma.relacaoOS.findUnique({
    where: { numeroOS },
    include: _includeCompleto,
  });
}

async function fecharOS(numeroOS, fechadoPorNome) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:  { numeroOS },
    data:   { status: 'FECHADA', fechadoPorNome: fechadoPorNome ?? null },
    include: _includeCompleto,
  });
}

async function dadosParaPDF(numeroOS) {
  const relacao = await buscarPorNumeroOS(numeroOS);
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };

  const saidas   = relacao.movimentacoes.filter((m) => m.tipo === 'SAIDA');
  const entradas = relacao.movimentacoes.filter((m) => m.tipo === 'ENTRADA');

  const _precoMov = (m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2   = Number(m.precoM2       || 0);
    return precoUnit > 0 ? precoUnit : precoM2;
  };

  const porMaterial = new Map();

  const todasOrdenadas = [...relacao.movimentacoes].sort(
    (a, b) => new Date(a.criadoEm) - new Date(b.criadoEm)
  );

  for (const m of todasOrdenadas) {
    const id = m.materialId;

    if (m.tipo === 'SAIDA') {
      if (!porMaterial.has(id)) {
        porMaterial.set(id, { preco: _precoMov(m), qtdSaida: 0, qtdEntrada: 0, valorRetalho: 0 });
      }
      const entry = porMaterial.get(id);
      if (_precoMov(m) > entry.preco) entry.preco = _precoMov(m);
      entry.qtdSaida += Number(m.quantidade);

    } else if (m.tipo === 'ENTRADA') {
      if (m.materialOrigemId != null && porMaterial.has(m.materialOrigemId)) {
        porMaterial.get(m.materialOrigemId).valorRetalho += _precoMov(m) * Number(m.quantidade);
        continue;
      }

      const isEntradaOC =
        (m.observacao   && m.observacao.includes('via OC')) ||
        (m.descricaoItem && m.descricaoItem.includes('via OC'));
      if (isEntradaOC) continue;

      if (porMaterial.has(id)) {
        porMaterial.get(id).qtdEntrada += Number(m.quantidade);
      }
    }
  }

  const totalSaidas = Array.from(porMaterial.values()).reduce((acc, { preco, qtdSaida, qtdEntrada }) => {
    const qtdLiquida = Math.max(0, qtdSaida - qtdEntrada);
    return acc + preco * qtdLiquida;
  }, 0);

  const totalGeral = Array.from(porMaterial.values()).reduce((acc, { preco, qtdSaida, qtdEntrada, valorRetalho }) => {
    const qtdLiquida   = Math.max(0, qtdSaida - qtdEntrada);
    const valorBruto   = preco * qtdLiquida;
    const valorLiquido = Math.max(0, valorBruto - valorRetalho);
    return acc + valorLiquido;
  }, 0);

  const _mapItem = (m) => {
    const precoUnit = Number(m.precoUnitario || 0);
    const precoM2v  = Number(m.precoM2       || 0);
    const usarM2    = precoUnit === 0 && precoM2v > 0;
    const preco     = usarM2 ? precoM2v : precoUnit;
    return {
      material:      m.material.nome,
      identificador: m.material.identificador ?? null,
      medida:        m.material.medida        ?? null,
      espessura:     m.material.espessura     ?? null,
      unidade:       m.material.unidade,
      categoria:     m.material.categoria,
      quantidade:    Number(m.quantidade),
      precoUnitario: preco,
      usarM2,
      total:         Number(m.quantidade) * preco,
      data:          m.criadoEm,
      observacao:    m.observacao,
      materialOrigemId:   m.materialOrigemId   ?? null,
      materialOrigemNome: m.materialOrigem?.nome ?? null,
    };
  };

  const _agruparPorMaterial = (itensMapeados, movsOriginais) => {
    const grupos = new Map();
    for (let i = 0; i < itensMapeados.length; i++) {
      const item = itensMapeados[i];
      const materialId = movsOriginais[i].materialId;
      if (!grupos.has(materialId)) {
        grupos.set(materialId, { ...item, observacoes: new Set(), origens: new Set() });
        const novoGrupo = grupos.get(materialId);
        if (item.observacao) novoGrupo.observacoes.add(item.observacao);
        if (item.materialOrigemNome) novoGrupo.origens.add(item.materialOrigemNome);
        continue;
      }
      const grupo = grupos.get(materialId);
      grupo.quantidade += item.quantidade;
      grupo.total       += item.total;
      if (new Date(item.data) > new Date(grupo.data)) grupo.data = item.data;
      if (item.precoUnitario > grupo.precoUnitario) grupo.precoUnitario = item.precoUnitario;
      if (item.observacao) grupo.observacoes.add(item.observacao);
      if (item.materialOrigemNome) grupo.origens.add(item.materialOrigemNome);
    }
    return Array.from(grupos.values()).map((g) => {
      const { observacoes, origens, ...resto } = g;
      return {
        ...resto,
        observacao:         observacoes.size > 0 ? Array.from(observacoes).join(' | ') : null,
        materialOrigemNome: origens.size > 0 ? Array.from(origens).join(', ') : null,
      };
    });
  };

  const todasMovs = [...relacao.movimentacoes];
  const primeiraMovimentacaoEm = todasMovs.length > 0
    ? todasMovs.reduce((a, b) => new Date(a.criadoEm) < new Date(b.criadoEm) ? a : b).criadoEm
    : relacao.criadoEm;

  return {
    numeroOS:              relacao.numeroOS,
    descricao:             relacao.descricao,
    cliente:               relacao.cliente,
    status:                relacao.status,
    criadoEm:              primeiraMovimentacaoEm,
    fechadaEm:             relacao.atualizadoEm,
    geradoEm:              new Date(),
    itens:                 _agruparPorMaterial(saidas.map(_mapItem), saidas),
    entradas:              _agruparPorMaterial(entradas.map(_mapItem), entradas),
    totalSaidas,
    totalGeral,
  };
}

async function reverterOS(numeroOS) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { numeroOS } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status !== 'FECHADA') {
    throw { status: 400, message: 'Esta OS não está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { numeroOS },
    data:    { status: 'EM_ANDAMENTO', fechadoPorNome: null },
    include: _includeCompleto,
  });
}

module.exports = { listar, buscarPorNumeroOS, fecharOS, reverterOS, dadosParaPDF };