const prisma = require('../utils/prisma');

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