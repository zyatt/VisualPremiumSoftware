// producao.service.js
const prisma = require('../utils/prisma');

// ── Include reutilizável ──────────────────────────────────────────────────────
const _includeSolicitacao = {
  material: {
    select: {
      id: true, nome: true, unidade: true, quantidade: true,
      estoqueMinimo: true, identificador: true, medida: true,
      espessura: true, categoria: true, especifico: true, status: true,
      ultimoValorPago: true, ultimoValorPagoM2: true,
    },
  },
  baixas: { orderBy: { criadoEm: 'asc' } },
};

// ── Helpers ───────────────────────────────────
function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _statusComReserva(estoqueAtual, emUso, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const disponivel = Number(estoqueAtual) + Number(emUso);
  const min        = Number(estoqueMinimo);
  if (disponivel > min)  return 'OK';
  if (disponivel === min) return 'LIMITE';
  return 'CRITICO';
}

async function _emUsoMaterial(materialId) {
  const ativas = await prisma.solicitacaoProducao.findMany({
    where: { materialId, status: { in: ['ABERTA', 'EM_USO'] } },
    select: { quantidadeReservada: true, quantidadeUsada: true },
  });
  return ativas.reduce((acc, s) => {
    const restante = Math.max(0, Number(s.quantidadeReservada) - Number(s.quantidadeUsada));
    return acc + restante;
  }, 0);
}

// ── Listar materiais (visão produção) ─────────────────────────────────────────
// Suporta filtros: busca (nome), categoria, status, id, identificador, medida, espessura
async function listarMateriais({ busca, categoria, status, id, identificador, medida, espessura } = {}) {
  const where = { ativo: true };

  if (id) {
    const idNum = parseInt(id, 10);
    if (!isNaN(idNum)) where.id = idNum;
  }
  if (busca)         where.nome           = { contains: busca,         mode: 'insensitive' };
  if (categoria)     where.categoria      = { equals:   categoria,     mode: 'insensitive' };
  if (identificador) where.identificador  = { contains: identificador, mode: 'insensitive' };
  if (medida)        where.medida         = { contains: medida,        mode: 'insensitive' };
  if (espessura)     where.espessura      = { contains: espessura,     mode: 'insensitive' };
  if (status)        where.status         = status;

  const materiais = await prisma.material.findMany({
    where,
    include: { estoquesEspecificos: true },
    orderBy: [{ categoria: 'asc' }, { nome: 'asc' }],
  });

  const resultado = await Promise.all(
    materiais.map(async (m) => {
      const emUso      = await _emUsoMaterial(m.id);
      const statusReal = _statusComReserva(m.quantidade, emUso, m.estoqueMinimo, m.ativo);
      return { ...m, emUso, statusReal };
    })
  );

  return resultado;
}

// ── Criar solicitação ─────────────────────────────────────────────────────────
async function criarSolicitacao({ materialId, descricaoItem, quantidadeReservada, numeroOS, usuarioId, usuarioNome }) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material || !material.ativo) throw { status: 404, message: 'Material não encontrado ou inativo' };

  // Normaliza o número da OS: sem espaços extras, maiúsculas
  const numeroOSNorm = (numeroOS ?? '').trim().toUpperCase();

  if (material.especifico) {
    const desc = (descricaoItem ?? '').trim();
    if (!desc) throw { status: 400, message: 'Materiais específicos exigem uma descrição' };

    const filho = await prisma.estoqueEspecifico.findUnique({
      where: { materialId_descricao: { materialId, descricao: desc } },
    });
    const saldo = filho ? Number(filho.quantidade) : 0;
    if (saldo < Number(quantidadeReservada)) {
      throw {
        status: 400,
        message: `Estoque insuficiente para "${desc}": disponível ${saldo} ${material.unidade ?? ''}`.trim(),
      };
    }
    const novaQtd = saldo - Number(quantidadeReservada);
    if (novaQtd === 0) {
      await prisma.estoqueEspecifico.delete({
        where: { materialId_descricao: { materialId, descricao: desc } },
      });
    } else {
      await prisma.estoqueEspecifico.update({
        where: { materialId_descricao: { materialId, descricao: desc } },
        data:  { quantidade: novaQtd },
      });
    }
  } else {
    const saldo = Number(material.quantidade);
    if (saldo < Number(quantidadeReservada)) {
      throw {
        status: 400,
        message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
      };
    }
    await prisma.material.update({
      where: { id: materialId },
      data:  { quantidade: { decrement: Number(quantidadeReservada) } },
    });
  }

  const qtd = Number(quantidadeReservada);

  // Recalcula status do material sem reserva pendente (solicitação já finalizada)
  const matAtualizado = await prisma.material.findUnique({ where: { id: materialId } });
  const emUso         = await _emUsoMaterial(materialId); // 0 reservas abertas
  const novoStatus    = _statusComReserva(matAtualizado.quantidade, emUso, matAtualizado.estoqueMinimo, matAtualizado.ativo);
  await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });

  // Cria já finalizada — sem passar por ABERTA/EM_USO
  const solicitacao = await prisma.solicitacaoProducao.create({
    data: {
      numeroOS: numeroOSNorm,
      materialId,
      descricaoItem: descricaoItem ?? null,
      quantidadeReservada: qtd,
      quantidadeUsada: qtd,
      status: 'FINALIZADA',
      finalizadoEm: new Date(),
      usuarioId,
      usuarioNome,
    },
    include: _includeSolicitacao,
  });

  await _registrarSaidaControleEstoque(solicitacao);

  return solicitacao;
}

// ── Registrar baixa ───────────────────────────────────────────────────────────
async function registrarBaixa({ solicitacaoId, quantidade, observacao }) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id: solicitacaoId },
    include: { material: true },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  if (sol.status === 'FINALIZADA') throw { status: 400, message: 'Solicitação já finalizada' };

  const restante = Number(sol.quantidadeReservada) - Number(sol.quantidadeUsada);
  if (Number(quantidade) > restante) {
    throw {
      status: 400,
      message: `Baixa (${quantidade}) excede o saldo em uso (${restante.toFixed(3)})`,
    };
  }

  const novaUsada = Number(sol.quantidadeUsada) + Number(quantidade);

  await prisma.baixaProducao.create({
    data: { solicitacaoId, quantidade: Number(quantidade), observacao: observacao ?? null },
  });

  // Atualiza status para EM_USO, mas NÃO finaliza automaticamente
  const atualizada = await prisma.solicitacaoProducao.update({
    where: { id: solicitacaoId },
    data: {
      quantidadeUsada: novaUsada,
      status: 'EM_USO',
    },
    include: _includeSolicitacao,
  });

  const mat    = await prisma.material.findUnique({ where: { id: sol.materialId } });
  const emUso  = await _emUsoMaterial(sol.materialId);
  const novoSt = _statusComReserva(mat.quantidade, emUso, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: sol.materialId }, data: { status: novoSt } });

  return atualizada;
}

// ── Finalizar solicitação ─────────────────────────────────────────────────────
async function finalizarSolicitacao({ solicitacaoId }) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id: solicitacaoId },
    include: { material: true, baixas: true },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  if (sol.status === 'FINALIZADA') throw { status: 400, message: 'Solicitação já finalizada' };

  const sobra = Math.max(0, Number(sol.quantidadeReservada) - Number(sol.quantidadeUsada));

  if (sobra > 0) {
    if (sol.material.especifico && sol.descricaoItem) {
      const desc = sol.descricaoItem.trim();
      await prisma.estoqueEspecifico.upsert({
        where:  { materialId_descricao: { materialId: sol.materialId, descricao: desc } },
        create: { materialId: sol.materialId, descricao: desc, quantidade: sobra },
        update: { quantidade: { increment: sobra } },
      });
    } else {
      await prisma.material.update({
        where: { id: sol.materialId },
        data:  { quantidade: { increment: sobra } },
      });
    }
  }

  const finalizada = await prisma.solicitacaoProducao.update({
    where: { id: solicitacaoId },
    data:  { status: 'FINALIZADA', finalizadoEm: new Date() },
    include: _includeSolicitacao,
  });

  if (Number(sol.quantidadeUsada) > 0) {
    await _registrarSaidaControleEstoque(finalizada);
  }

  const mat    = await prisma.material.findUnique({ where: { id: sol.materialId } });
  const emUso  = await _emUsoMaterial(sol.materialId);
  const novoSt = _statusComReserva(mat.quantidade, emUso, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: sol.materialId }, data: { status: novoSt } });

  return finalizada;
}

// ── Excluir registro do histórico ─────────────────────────────────────────────
// Apenas solicitações FINALIZADAS podem ser excluídas.
// A exclusão remove somente o registro histórico; o estoque já foi
// acertado no momento da finalização, portanto não há reversão.
async function excluirHistorico(solicitacaoId) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where: { id: solicitacaoId },
  });
  if (!sol) throw { status: 404, message: 'Registro não encontrado' };
  if (sol.status !== 'FINALIZADA') {
    throw { status: 400, message: 'Somente solicitações finalizadas podem ser excluídas do histórico' };
  }

  // BaixaProducao tem onDelete: Cascade, portanto são removidas automaticamente
  await prisma.solicitacaoProducao.delete({ where: { id: solicitacaoId } });
}

// ── Registrar saída no controle de estoque ────────────────────────────────────
async function _registrarSaidaControleEstoque(sol) {
  const qtdUsada = Number(sol.quantidadeUsada);
  if (qtdUsada <= 0) return;

  const observacao = `Saída via produção – ${sol.usuarioNome}`;
  const numeroOS   = sol.numeroOS;

  // Busca o preço do material (último valor pago registrado)
  const material = sol.material ?? await prisma.material.findUnique({
    where: { id: sol.materialId },
    select: { ultimoValorPago: true, ultimoValorPagoM2: true },
  });
  const precoUnitario = material?.ultimoValorPago   ? Number(material.ultimoValorPago)   : null;
  const precoM2       = material?.ultimoValorPagoM2 ? Number(material.ultimoValorPagoM2) : null;

  // Para material específico (filho), tenta pegar o preço do estoque específico
  let precoUnitarioFinal = precoUnitario;
  let precoM2Final       = precoM2;
  if (sol.descricaoItem) {
    const filho = await prisma.estoqueEspecifico.findUnique({
      where: { materialId_descricao: { materialId: sol.materialId, descricao: sol.descricaoItem.trim() } },
      select: { ultimoValorPago: true, ultimoValorPagoM2: true },
    }).catch(() => null);
    if (filho?.ultimoValorPago)   precoUnitarioFinal = Number(filho.ultimoValorPago);
    if (filho?.ultimoValorPagoM2) precoM2Final       = Number(filho.ultimoValorPagoM2);
  }

  // Busca ou cria a RelacaoOS adequada.
  //
  // Regra (espelha estoque_service):
  //  • OS numérica  → reutiliza sempre (upsert pelo numeroOS exato).
  //  • OS textual   → reutiliza se EM_ANDAMENTO (nome exato OU sufixo de data de hoje).
  //    Se já estiver FECHADA, cria uma nova com sufixo de data para não
  //    contaminar um período anterior já encerrado.
  const osEhNumerica = /^\d+$/.test(numeroOS);

  const _d   = new Date();
  const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`; // "DD-MM-YYYY"

  let relacao;
  if (osEhNumerica) {
    // OS numérica: upsert garante uma única relação por chave exata
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    // OS textual: procura qualquer RelacaoOS EM_ANDAMENTO com o nome exato
    // OU com sufixo de data de hoje (criada pelo controle de estoque no mesmo dia)
    const relacaoAberta = await prisma.relacaoOS.findFirst({
      where: {
        status: 'EM_ANDAMENTO',
        OR: [
          { numeroOS: numeroOS },
          { numeroOS: { startsWith: `${numeroOS}-${hoje}` } },
        ],
      },
      orderBy: { criadoEm: 'asc' },
    });

    if (relacaoAberta) {
      relacao = relacaoAberta;
    } else {
      // Nenhuma aberta: cria nova com sufixo de data
      let candidato = `${numeroOS}-${hoje}`;
      let sufixoSeq = 1;

      while (true) {
        const existente = await prisma.relacaoOS.findUnique({ where: { numeroOS: candidato } });
        if (!existente) {
          relacao = await prisma.relacaoOS.create({ data: { numeroOS: candidato, status: 'EM_ANDAMENTO' } });
          break;
        }
        if (existente.status !== 'FECHADA') {
          relacao = existente;
          break;
        }
        sufixoSeq += 1;
        candidato = `${numeroOS}-${hoje}-${sufixoSeq}`;
      }
    }
  }

  await prisma.movimentacaoEstoque.create({
    data: {
      materialId:    sol.materialId,
      tipo:          'SAIDA',
      quantidade:    qtdUsada,
      numeroOS,
      relacaoOSId:   relacao.id,
      descricaoItem: sol.descricaoItem ?? null,
      observacao,
      precoUnitario: precoUnitarioFinal ?? undefined,
      precoM2:       precoM2Final       ?? undefined,
    },
  });
}

// ── Listar solicitações ───────────────────────────────────────────────────────
async function listarSolicitacoes({ usuarioId, status, busca } = {}) {
  const where = {};
  if (usuarioId) where.usuarioId = usuarioId;
  if (status)    where.status    = Array.isArray(status) ? { in: status } : status;
  if (busca)     where.OR = [
    { numeroOS:    { contains: busca, mode: 'insensitive' } },
    { usuarioNome: { contains: busca, mode: 'insensitive' } },
  ];

  return prisma.solicitacaoProducao.findMany({
    where,
    include: _includeSolicitacao,
    orderBy: { atualizadoEm: 'desc' },
  });
}

// ── Buscar uma solicitação ────────────────────────────────────────────────────
async function buscarSolicitacao(id) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id },
    include: _includeSolicitacao,
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  return sol;
}

// ── Listar categorias de materiais ────────────────────────────────────────────
async function listarCategorias() {
  const cats = await prisma.material.findMany({
    where:    { ativo: true, categoria: { not: null } },
    select:   { categoria: true },
    distinct: ['categoria'],
    orderBy:  { categoria: 'asc' },
  });
  return cats.map((c) => c.categoria).filter(Boolean);
}

module.exports = {
  listarMateriais,
  criarSolicitacao,
  registrarBaixa,
  finalizarSolicitacao,
  excluirHistorico,
  listarSolicitacoes,
  buscarSolicitacao,
  listarCategorias,
};