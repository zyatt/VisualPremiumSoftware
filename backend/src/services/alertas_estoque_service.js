const prisma = require('../utils/prisma');

/**
 * Retorna todos os materiais ativos com status CRITICO,
 * ordenados por nome.
 *
 * Campos retornados são um subconjunto de Material para manter o payload leve,
 * alinhado com AlertaEstoqueModel no Flutter.
 */
async function listarAlertasEstoque() {
  const materiais = await prisma.material.findMany({
    where: {
      ativo:  true,
      status: 'CRITICO',
    },
    select: {
      id:            true,
      nome:          true,
      categoria:     true,
      unidade:       true,
      identificador: true,
      medida:        true,
      espessura:     true,
      quantidade:    true,
      estoqueMinimo: true,
      status:        true,
    },
    orderBy: { nome: 'asc' },
  });

  return materiais.map((m) => ({
    id:            m.id,
    nome:          m.nome,
    categoria:     m.categoria     ?? null,
    unidade:       m.unidade       ?? null,
    identificador: m.identificador ?? null,
    medida:        m.medida        ?? null,
    espessura:     m.espessura     ?? null,
    quantidade:    Number(m.quantidade),
    estoqueMinimo: Number(m.estoqueMinimo),
    status:        m.status,
  }));
}

module.exports = { listarAlertasEstoque };