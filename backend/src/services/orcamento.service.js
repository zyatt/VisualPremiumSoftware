const prisma = require('../utils/prisma');

const _itensInclude = {
  itens: {
    include: {
      material: {
        select: {
          id: true,
          nome: true,
          unidade: true,
          categoria: true,
          medida: true,
          espessura: true,
          identificador: true,
        },
      },
      fornecedor: { select: { id: true, nomeFantasia: true } },
    },
  },
  aprovador: { select: { id: true, nome: true } },
  criador:   { select: { id: true, nome: true } },
};

async function listar(status) {
  const where = {};
  if (status) where.status = status;

  return prisma.orcamento.findMany({
    where,
    include: _itensInclude,
    orderBy: { criadoEm: 'desc' },
  });
}

async function buscarPorId(id) {
  return prisma.orcamento.findUnique({
    where: { id },
    include: {
      itens: {
        include: {
          material: {
            include: {
              fornecedorMateriais: {
                where: { ativo: true },
                include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
              },
            },
          },
          fornecedor: true,
        },
      },
      aprovador: { select: { id: true, nome: true } },
    },
  });
}

async function criar(titulo, criadorId) {
  const orc = await prisma.orcamento.create({
    data: { criadorId: criadorId ?? null },
  });
  const tituloFinal = titulo?.trim() ? titulo.trim() : `Orçamento #${orc.id}`;
  return prisma.orcamento.update({
    where: { id: orc.id },
    data: { titulo: tituloFinal },
  });
}

async function adicionarItem(
  orcamentoId, materialId, fornecedorId, quantidade, precoUnitario,
  { selecionado = false, descricaoItem = null, observacao = null } = {}
  ) {
  const data = {
    fornecedorId: fornecedorId ?? null,
    quantidade,
    precoUnitario: precoUnitario ?? null,
    selecionado: selecionado ?? false,
    descricaoItem: descricaoItem ?? null,
    observacao: observacao ?? null,
  };

  const existente = await prisma.orcamentoItem.findFirst({
    where: { orcamentoId, materialId, fornecedorId: fornecedorId ?? null },
  });

  if (existente) {
    return prisma.orcamentoItem.update({ where: { id: existente.id }, data });
  }

  return prisma.orcamentoItem.create({
    data: { orcamentoId, materialId, ...data },
  });
}

async function removerItem(orcamentoId, itemId) {
  return prisma.orcamentoItem.deleteMany({ where: { id: itemId, orcamentoId } });
}

async function limparItens(orcamentoId) {
  return prisma.orcamentoItem.deleteMany({ where: { orcamentoId } });
}

async function atualizarItem(itemId, data) {
  return prisma.orcamentoItem.update({ where: { id: itemId }, data });
}

async function cancelar(id) {
  return prisma.orcamento.update({ where: { id }, data: { status: 'CANCELADO' } });
}

async function enviarParaAprovacao(id) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id },
    include: { itens: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'ABERTO' && orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos abertos podem ser enviados para aprovação' };

  if (orcamento.itens.length === 0)
    throw { status: 400, message: 'Não é possível enviar um orçamento vazio para aprovação' };

  return prisma.orcamento.update({
    where: { id },
    data: { status: 'AGUARDANDO_APROVACAO' },
  });
}

async function aprovar(id, aprovadorId) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos aguardando aprovação podem ser aprovados' };

  return prisma.orcamento.update({
    where: { id },
    data: {
      status: 'APROVADO',
      aprovadorId,
      aprovadoEm: new Date(),
      motivoRejeicao: null,
    },
  });
}

async function rejeitar(id, aprovadorId, motivo) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'AGUARDANDO_APROVACAO')
    throw { status: 400, message: 'Apenas orçamentos aguardando aprovação podem ser rejeitados' };

  return prisma.orcamento.update({
    where: { id },
    data: {
      status: 'NAO_APROVADO',
      aprovadorId,
      aprovadoEm: new Date(),
      motivoRejeicao: motivo || 'Não informado',
    },
  });
}

async function validarParaOC(orcamentoId) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    include: { itens: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  if (orcamento.status !== 'APROVADO' && orcamento.status !== 'ABERTO')
    throw { status: 400, message: 'Apenas orçamentos aprovados (ou reabertos de aprovado) podem gerar ordem de compra' };

  if (orcamento.itens.length === 0)
    throw { status: 400, message: 'Orçamento não possui itens' };

  return true;
}

async function reabrir(id) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const statusPermitidos = ['AGUARDANDO_APROVACAO', 'APROVADO', 'NAO_APROVADO'];
  if (!statusPermitidos.includes(orcamento.status))
    throw {
      status: 400,
      message: 'Apenas orçamentos aguardando aprovação, aprovados ou não aprovados podem ser reabertos',
    };

  return prisma.orcamento.update({
    where: { id },
    data: {
      status: 'ABERTO',
      aprovadorId: null,
      aprovadoEm: null,
      motivoRejeicao: null,
    },
    include: _itensInclude,
  });
}

async function atualizar(id, dados) {
  return prisma.orcamento.update({ where: { id }, data: dados });
}

async function excluir(id) {
  const orcamento = await prisma.orcamento.findUnique({ where: { id } });
  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const statusPermitidos = ['CANCELADO', 'NAO_APROVADO', 'CONVERTIDO'];
  if (!statusPermitidos.includes(orcamento.status)) {
    throw {
      status: 400,
      message: 'Apenas orçamentos cancelados, rejeitados ou convertidos podem ser excluídos',
    };
  }

  await prisma.orcamentoItem.deleteMany({ where: { orcamentoId: id } });
  await prisma.orcamento.delete({ where: { id } });
}

async function definirFornecedorOculto(orcamentoId, fornecedorId, oculto) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    select: { fornecedoresOcultos: true },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const atual = new Set(orcamento.fornecedoresOcultos);
  if (oculto) atual.add(fornecedorId);
  else atual.delete(fornecedorId);

  return prisma.orcamento.update({
    where: { id: orcamentoId },
    data: { fornecedoresOcultos: Array.from(atual) },
  });
}

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  excluir,
  adicionarItem,
  removerItem,
  limparItens,
  atualizarItem,
  cancelar,
  enviarParaAprovacao,
  aprovar,
  rejeitar,
  validarParaOC,
  reabrir,
  definirFornecedorOculto,
};