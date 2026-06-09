const prisma = require('../utils/prisma');

// ─── Veículos ────────────────────────────────────────────────────────────────

async function listarVeiculos() {
  return prisma.veiculo.findMany({
    where: { ativo: true },
    include: {
      manutencoes: {
        orderBy: { dataEnvio: 'desc' },
        take: 1,
      },
    },
    orderBy: { nome: 'asc' },
  });
}

async function criarVeiculo({ nome, placa }) {
  if (!nome || !placa) {
    const err = new Error('Nome e placa são obrigatórios.');
    err.status = 400;
    throw err;
  }
  return prisma.veiculo.create({ data: { nome, placa: placa.toUpperCase() } });
}

async function atualizarVeiculo(id, { nome, placa }) {
  const data = {};
  if (nome  !== undefined) data.nome  = nome;
  if (placa !== undefined) data.placa = placa.toUpperCase();
  return prisma.veiculo.update({ where: { id }, data });
}

async function desativarVeiculo(id) {
  return prisma.veiculo.update({ where: { id }, data: { ativo: false } });
}

// ─── Manutenções ─────────────────────────────────────────────────────────────

async function listarManutencoes(veiculoId) {
  return prisma.manutencaoVeiculo.findMany({
    where: { veiculoId },
    orderBy: { dataEnvio: 'desc' },
  });
}

async function criarManutencao({ veiculoId, tipo, descricao, valor, dataEnvio, dataRetirada }) {
  if (!veiculoId || !tipo || valor == null || !dataEnvio) {
    const err = new Error('Campos obrigatórios: veiculoId, tipo, valor, dataEnvio.');
    err.status = 400;
    throw err;
  }
  return prisma.manutencaoVeiculo.create({
    data: {
      veiculoId,
      tipo,
      descricao,
      valor,
      dataEnvio:    new Date(dataEnvio),
      dataRetirada: dataRetirada ? new Date(dataRetirada) : null,
    },
  });
}

async function atualizarManutencao(id, { tipo, descricao, valor, dataEnvio, dataRetirada }) {
  const data = {};
  if (tipo         !== undefined) data.tipo         = tipo;
  if (descricao    !== undefined) data.descricao    = descricao;
  if (valor        !== undefined) data.valor        = valor;
  if (dataEnvio    !== undefined) data.dataEnvio    = new Date(dataEnvio);
  if (dataRetirada !== undefined)
    data.dataRetirada = dataRetirada ? new Date(dataRetirada) : null;
  return prisma.manutencaoVeiculo.update({ where: { id }, data });
}

async function deletarManutencao(id) {
  return prisma.manutencaoVeiculo.delete({ where: { id } });
}

// ─── Gastos (para a página de gastos) ────────────────────────────────────────

/**
 * Retorna gastos de veículos agrupados por veículo.
 * Filtros opcionais: dataInicio / dataFim (sobre dataEnvio).
 */
async function gastosPorVeiculo({ dataInicio, dataFim } = {}) {
  const where = {};

  if (dataInicio || dataFim) {
    const filtroData = {};
    if (dataInicio) filtroData.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      filtroData.lte = fim;
    }
    where.dataEnvio = filtroData;
  }

  const manutencoes = await prisma.manutencaoVeiculo.findMany({
    where,
    include: { veiculo: { select: { id: true, nome: true, placa: true } } },
    orderBy: { dataEnvio: 'asc' },
  });

  const porVeiculo = {};

  for (const m of manutencoes) {
    const vid = m.veiculo.id;
    if (!porVeiculo[vid]) {
      porVeiculo[vid] = {
        veiculoId:   vid,
        nome:        m.veiculo.nome,
        placa:       m.veiculo.placa,
        totalGasto:  0,
        qtdServicos: 0,
        servicos:    [],
      };
    }
    const g = porVeiculo[vid];
    const v = Number(m.valor);
    g.totalGasto  += v;
    g.qtdServicos += 1;
    g.servicos.push({
      id:           m.id,
      tipo:         m.tipo,
      descricao:    m.descricao,
      valor:        v,
      dataEnvio:    m.dataEnvio,
      dataRetirada: m.dataRetirada,
    });
  }

  return Object.values(porVeiculo).sort((a, b) => b.totalGasto - a.totalGasto);
}

/**
 * Resumo mensal/anual dos gastos com veículos.
 */
async function resumoGastosVeiculo({ ano } = {}) {
  const anoAlvo = ano ? parseInt(ano, 10) : new Date().getFullYear();

  const manutencoes = await prisma.manutencaoVeiculo.findMany({
    where: {
      dataEnvio: {
        gte: new Date(`${anoAlvo}-01-01`),
        lte: new Date(`${anoAlvo}-12-31T23:59:59.999Z`),
      },
    },
    select: { valor: true, dataEnvio: true },
  });

  // Agrupa por mês (1–12)
  const porMes = Array.from({ length: 12 }, (_, i) => ({
    mes:        i + 1,
    totalGasto: 0,
  }));

  let totalAnual = 0;
  for (const m of manutencoes) {
    const mes = new Date(m.dataEnvio).getMonth(); // 0-indexed
    const v   = Number(m.valor);
    porMes[mes].totalGasto += v;
    totalAnual              += v;
  }

  return { ano: anoAlvo, totalAnual, porMes };
}

module.exports = {
  listarVeiculos,
  criarVeiculo,
  atualizarVeiculo,
  desativarVeiculo,
  listarManutencoes,
  criarManutencao,
  atualizarManutencao,
  deletarManutencao,
  gastosPorVeiculo,
  resumoGastosVeiculo,
};