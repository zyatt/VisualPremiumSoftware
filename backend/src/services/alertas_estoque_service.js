const prisma = require('../utils/prisma');

/**
 * Retorna todos os materiais ativos com status CRITICO ou LIMITE,
 * ordenados: CRITICO primeiro, depois LIMITE; dentro de cada grupo, por nome.
 *
 * Campos retornados são um subconjunto de Material para manter o payload leve,
 * alinhado com AlertaEstoqueModel no Flutter.
 */
async function listarAlertasEstoque() {
  const materiais = await prisma.material.findMany({
    where: {
      ativo:  true,
      status: { in: ['CRITICO', 'LIMITE'] },
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
      especifico:    true,
    },
    orderBy: [
      // CRITICO antes de LIMITE (ordem alfabética inversa: C < L)
      { status: 'asc' },
      { nome:   'asc' },
    ],
  });

  // Garante CRITICO antes de LIMITE independente da collation do banco
  materiais.sort((a, b) => {
    if (a.status === b.status) return a.nome.localeCompare(b.nome);
    return a.status === 'CRITICO' ? -1 : 1;
  });

  return materiais.map((m) => ({
    id:            m.id,
    nome:          m.nome,
    categoria:     m.categoria    ?? null,
    unidade:       m.unidade      ?? null,
    identificador: m.identificador ?? null,
    medida:        m.medida       ?? null,
    espessura:     m.espessura    ?? null,
    quantidade:    Number(m.quantidade),
    estoqueMinimo: Number(m.estoqueMinimo),
    status:        m.status,
    especifico:    m.especifico,
  }));
}

module.exports = { listarAlertasEstoque };