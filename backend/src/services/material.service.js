const prisma = require('../utils/prisma');

// Recalcula status baseado em quantidade vs estoqueMinimo
function calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _throwDuplicado(medida, espessura) {
  const partes = ['nome'];
  if (medida)    partes.push('medida');
  if (espessura) partes.push('espessura');
  throw {
    status: 409,
    message: `Já existe um material com o mesmo ${partes.join(', ')}. Altere a medida ou a espessura para diferenciar.`,
  };
}

async function listar(filtros = {}) {
  const { busca, categoria, status, comFornecedor, id, medida, espessura, ativo } = filtros;

  // Sem filtro de ativo: inativos aparecem ofuscados na lista (exceto quando ativo=true explícito)
  const where = {};
  if (ativo === 'true') where.ativo = true;
  if (id) where.id = Number(id);
  if (busca) where.nome = { contains: busca, mode: 'insensitive' };
  if (medida) where.medida = { contains: medida, mode: 'insensitive' };
  if (espessura) where.espessura = { contains: espessura, mode: 'insensitive' };
  if (categoria) where.categoria = { contains: categoria, mode: 'insensitive' };
  if (status) where.status = status;
  if (comFornecedor === 'true') {
    where.fornecedorMateriais = { some: { ativo: true } };
  }

  const materiais = await prisma.material.findMany({
    where,
    include: {
      fornecedorMateriais: {
        where: { ativo: true },
        include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
      },
    },
    // Ativos primeiro, depois inativos ao final
    orderBy: [{ ativo: 'desc' }, { nome: 'asc' }],
  });

  return materiais.map((m) => {
    const precos = m.fornecedorMateriais
      .map((fm) => Number(fm.preco))
      .filter((p) => p > 0)
      .sort((a, b) => a - b);

    const precosM2 = m.fornecedorMateriais
      .map((fm) => Number(fm.precoMetroQuadrado))
      .filter((p) => p > 0)
      .sort((a, b) => a - b);

    const mediana = (arr) => {
      if (!arr.length) return null;
      const mid = Math.floor(arr.length / 2);
      return arr.length % 2 !== 0 ? arr[mid] : (arr[mid - 1] + arr[mid]) / 2;
    };

    return {
      ...m,
      precoMediano: mediana(precos),
      precoM2Mediano: mediana(precosM2),
    };
  });
}

async function buscarPorId(id) {
  return prisma.material.findUnique({
    where: { id },
    include: {
      fornecedorMateriais: {
        include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
      },
    },
  });
}

async function criar(data) {
  // Valida duplicidade: nome + medida + espessura não podem ser todos iguais
  const nomeTrimmed      = data.nome?.trim();
  const medidaTrimmed    = data.medida?.trim()    ?? null;
  const espessuraTrimmed = data.espessura?.trim() ?? null;

  const duplicado = await prisma.material.findFirst({
    where: {
      nome:      { equals: nomeTrimmed, mode: 'insensitive' },
      medida:    medidaTrimmed    ? { equals: medidaTrimmed,    mode: 'insensitive' } : null,
      espessura: espessuraTrimmed ? { equals: espessuraTrimmed, mode: 'insensitive' } : null,
    },
  });

  if (duplicado) _throwDuplicado(medidaTrimmed, espessuraTrimmed);

  const status = calcularStatus(data.quantidade || 0, data.estoqueMinimo || 0, true);
  try {
    return await prisma.material.create({ data: { ...data, status } });
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function atualizar(id, data) {
  const atual = await prisma.material.findUnique({ where: { id } });

  // Valida duplicidade ao alterar nome, medida ou espessura
  const nomeTrimmed      = (data.nome      ?? atual.nome)?.trim();
  const medidaTrimmed    = (data.medida     ?? atual.medida)?.trim()    ?? null;
  const espessuraTrimmed = (data.espessura  ?? atual.espessura)?.trim() ?? null;

  const duplicado = await prisma.material.findFirst({
    where: {
      id:        { not: id },
      nome:      { equals: nomeTrimmed, mode: 'insensitive' },
      medida:    medidaTrimmed    ? { equals: medidaTrimmed,    mode: 'insensitive' } : null,
      espessura: espessuraTrimmed ? { equals: espessuraTrimmed, mode: 'insensitive' } : null,
    },
  });

  if (duplicado) _throwDuplicado(medidaTrimmed, espessuraTrimmed);

  const quantidade    = data.quantidade   ?? atual.quantidade;
  const estoqueMinimo = data.estoqueMinimo ?? atual.estoqueMinimo;
  const ativo         = data.ativo        ?? atual.ativo;
  const status = calcularStatus(quantidade, estoqueMinimo, ativo);
  try {
    return await prisma.material.update({ where: { id }, data: { ...data, status } });
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function desativar(id) {
  // CORRIGIDO: where só é válido em relações to-many (ordemItens), não dentro
  // do include de uma relação to-one (ordemCompra). Usamos _count com filtro aninhado.
  const material = await prisma.material.findUnique({
    where: { id },
    include: {
      _count: {
        select: {
          ordemItens: {
            where: {
              ordemCompra: { status: 'EM_ANDAMENTO' },
            },
          },
        },
      },
    },
  });

  if (!material) throw { status: 404, message: 'Material não encontrado' };

  const ordensAtivas = material._count.ordemItens;
  if (ordensAtivas > 0) {
    throw { status: 400, message: `Material vinculado a ${ordensAtivas} ordem(ns) em andamento` };
  }

  return prisma.material.update({
    where: { id },
    data: { ativo: false, status: 'INATIVO' },
  });
}

async function reativar(id) {
  const material = await prisma.material.findUnique({ where: { id } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  if (material.ativo) throw { status: 400, message: 'Material já está ativo' };

  // Recalcula status com base na quantidade atual
  const status = calcularStatus(material.quantidade, material.estoqueMinimo, true);

  return prisma.material.update({
    where: { id },
    data: { ativo: true, status },
  });
}

async function excluir(id) {
  const material = await prisma.material.findUnique({ where: { id } });
  if (material.ativo) throw { status: 400, message: 'Desative o material antes de excluí-lo' };
  return prisma.material.delete({ where: { id } });
}

async function confirmarEstoque(id) {
  return prisma.material.update({ where: { id }, data: { estoqueConfirmado: true } });
}

async function listarCategorias() {
  const result = await prisma.material.findMany({
    where: { ativo: true, categoria: { not: null } },
    select: { categoria: true },
    distinct: ['categoria'],
    orderBy: { categoria: 'asc' },
  });
  return result.map((r) => r.categoria);
}

module.exports = { listar, buscarPorId, criar, atualizar, desativar, reativar, excluir, confirmarEstoque, listarCategorias };