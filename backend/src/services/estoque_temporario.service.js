// estoque_temporario.service.js
// Materiais temporários são Materiais normais com temporario = true.
// Ao invés de deletar, o backend desativa (ativo = false) quando desativaEm chega.
const prisma = require('../utils/prisma');

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Retorna a data de desativação automática: hoje + 3 meses. */
function _desativaEm() {
  const d = new Date();
  d.setMonth(d.getMonth() + 3);
  return d;
}

/** Campos selecionados na resposta — apenas os relevantes para o frontend. */
const _select = {
  id:                   true,
  nome:                 true,
  unidade:              true,
  categoria:            true,
  ativo:                true,
  temporario:           true,
  desativaEm:           true,
  observacaoTemporario: true,
  criadoPorNome:        true,
  criadoEm:             true,
  atualizadoEm:         true,
};

// ── CRUD ─────────────────────────────────────────────────────────────────────

/**
 * Lista todos os materiais temporários (ativos e desativados).
 * Desativados continuam aparecendo para permitir reativação,
 * mas vêm depois dos ativos na ordenação.
 * Aplica filtro de busca por nome se informado.
 */
async function listar(busca) {
  const where = { temporario: true };
  if (busca) {
    where.nome = { contains: busca.trim(), mode: 'insensitive' };
  }
  return prisma.material.findMany({
    where,
    select:  _select,
    orderBy: [
      { ativo:    'desc' },
      { criadoEm: 'desc' },
    ],
  });
}

/**
 * Cria um Material normal marcado como temporário.
 * Campos opcionais de catálogo (categoria, medida, espessura, dimensões,
 * estoqueMinimo) ficam null/0 — podem ser preenchidos depois via tela de materiais.
 */
async function criar({ nome, unidade, categoria, observacao }, usuarioNome) {
  const nomeTrimmed = (nome ?? '').trim().toUpperCase();
  if (!nomeTrimmed) throw { status: 400, message: 'Nome é obrigatório' };

  // Verifica duplicidade: mesmo nome sem identificador/medida/espessura
  const existe = await prisma.material.findFirst({
    where: {
      nome:          nomeTrimmed,
      identificador: null,
      medida:        null,
      espessura:     null,
    },
  });
  if (existe) {
    throw {
      status: 409,
      message: `Já existe um material com o nome "${nomeTrimmed}"`,
    };
  }

  return prisma.material.create({
    data: {
      nome:                 nomeTrimmed,
      unidade:              (unidade ?? 'UNIDADE').toUpperCase(),
      categoria:            categoria?.trim() || null,
      temporario:           true,
      desativaEm:           _desativaEm(),
      observacaoTemporario: observacao?.trim() || null,
      criadoPorNome:        usuarioNome ?? null,
      // Campos padrão para material recém-criado
      quantidade:           0,
      estoqueMinimo:        0,
      ativo:                true,
    },
    select: _select,
  });
}

/**
 * Atualiza nome, unidade, categoria e/ou observação de um material temporário.
 * Renova também a data de desativação (mais 3 meses a partir de agora).
 */
async function atualizar(id, { nome, unidade, categoria, observacao }) {
  const item = await prisma.material.findUnique({ where: { id } });
  if (!item)           throw { status: 404, message: 'Material não encontrado' };
  if (!item.temporario) throw { status: 400, message: 'Material não é temporário' };
  if (!item.ativo)      throw { status: 400, message: 'Material já está desativado' };

  const nomeTrimmed = ((nome ?? item.nome) || '').trim().toUpperCase();
  if (!nomeTrimmed) throw { status: 400, message: 'Nome é obrigatório' };

  return prisma.material.update({
    where: { id },
    data: {
      nome:                 nomeTrimmed,
      unidade:              unidade ? unidade.toUpperCase() : item.unidade,
      categoria:            categoria !== undefined ? (categoria?.trim() || null) : item.categoria,
      observacaoTemporario: observacao !== undefined ? (observacao?.trim() || null) : item.observacaoTemporario,
      // Renova o prazo de desativação a cada edição
      desativaEm:           _desativaEm(),
    },
    select: _select,
  });
}

/**
 * "Remove" um material temporário desativando-o (ativo = false).
 * O registro permanece no banco para histórico e integridade referencial.
 */
async function remover(id) {
  const item = await prisma.material.findUnique({ where: { id } });
  if (!item)           throw { status: 404, message: 'Material não encontrado' };
  if (!item.temporario) throw { status: 400, message: 'Material não é temporário' };

  return prisma.material.update({
    where: { id },
    data:  { ativo: false },
    select: _select,
  });
}

/**
 * Reativa um material temporário previamente desativado (ativo = true)
 * e renova o prazo de desativação para mais 3 meses a partir de agora.
 */
async function reativar(id) {
  const item = await prisma.material.findUnique({ where: { id } });
  if (!item)            throw { status: 404, message: 'Material não encontrado' };
  if (!item.temporario)  throw { status: 400, message: 'Material não é temporário' };
  if (item.ativo)        throw { status: 400, message: 'Material já está ativo' };

  return prisma.material.update({
    where: { id },
    data: {
      ativo:      true,
      desativaEm: _desativaEm(),
    },
    select: _select,
  });
}

/**
 * Desativa automaticamente todos os materiais temporários cujo desativaEm já passou.
 * Chamar via cron ou a cada listagem.
 * Retorna o número de registros desativados.
 */
async function desativarExpirados() {
  const result = await prisma.material.updateMany({
    where: {
      temporario: true,
      ativo:      true,
      desativaEm: { lte: new Date() },
    },
    data: { ativo: false },
  });
  return result.count;
}

module.exports = { listar, criar, atualizar, remover, reativar, desativarExpirados };