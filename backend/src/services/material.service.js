const prisma = require('../utils/prisma');

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

function _normalizarPreco(valor) {
  if (valor == null) return null;
  const num = Number(valor);
  return num > 0 ? num : null;
}

async function listar(filtros = {}) {
  const { busca, categoria, semCategoria, status, comFornecedor, id, medida, espessura, identificador, ativo } = filtros;

  const where = {};
  if (ativo === 'true') where.ativo = true;
  if (id) where.id = Number(id);
  if (busca) {
    const tokens = busca.trim().split(/\s+/).filter(Boolean);
    if (tokens.length === 1) {
      where.nome = { contains: tokens[0], mode: 'insensitive' };
    } else {
      where.AND = (where.AND ?? []).concat(
        tokens.map((t) => ({ nome: { contains: t, mode: 'insensitive' } }))
      );
    }
  }
  if (identificador) where.identificador = { contains: identificador, mode: 'insensitive' };
  if (medida)        where.medida        = { contains: medida,        mode: 'insensitive' };
  if (espessura)     where.espessura     = { contains: espessura,     mode: 'insensitive' };
  if (semCategoria === 'true') {
    where.categoria = null;
  } else if (categoria) {
    where.categoria = { equals: categoria, mode: 'insensitive' };
  }
  if (status)              where.status = status;
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
      // ▼ NOVO: inclui filhos de estoque específico
      estoquesEspecificos: {
        orderBy: { descricao: 'asc' },
      },
    },
    orderBy: [{ ativo: 'desc' }, { nome: 'asc' }],
  });

  // Para materiais específicos, busca o último preço de ENTRADA por descricaoItem
  const idsEspecificos = materiais.filter((m) => m.especifico).map((m) => m.id);
  const ultimasMovimentacoes = idsEspecificos.length
  ? await prisma.movimentacaoEstoque.findMany({
      where: {
        materialId:    { in: idsEspecificos },
        tipo:          'ENTRADA',
        descricaoItem: { not: null },
        OR: [                          // ← era só precoUnitario: { not: null }
          { precoUnitario: { not: null } },
          { precoM2:       { not: null } },
        ],
      },
      orderBy: { criadoEm: 'desc' },
      select: {
        materialId:    true,
        descricaoItem: true,
        precoUnitario: true,
        precoM2:       true,
      },
    })
  : [];

  // Monta mapa: `${materialId}__${descricaoItem}` → { precoUnitario, precoM2 }
  // Como está ordenado desc, o primeiro encontrado por chave é o mais recente
  const precoFilhoMap = new Map();
  for (const mov of ultimasMovimentacoes) {
    const chave = `${mov.materialId}__${mov.descricaoItem}`;
    if (!precoFilhoMap.has(chave)) {
      precoFilhoMap.set(chave, {
        ultimoValorPago:   mov.precoUnitario != null ? Number(mov.precoUnitario) : null,
        ultimoValorPagoM2: mov.precoM2       != null ? Number(mov.precoM2)       : null,
      });
    }
  }

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

    const custoUltimaCompra   = _normalizarPreco(m.ultimoValorPago);
    const custoM2UltimaCompra = _normalizarPreco(m.ultimoValorPagoM2);

    // Enriquece filhos específicos com o último custo de ENTRADA por descrição
    const estoquesEspecificosEnriquecidos = m.especifico
      ? m.estoquesEspecificos.map((filho) => {
          const chave  = `${m.id}__${filho.descricao}`;
          const precos = precoFilhoMap.get(chave) ?? { ultimoValorPago: null, ultimoValorPagoM2: null };
          return { ...filho, ...precos };
        })
      : m.estoquesEspecificos;

    return {
      ...m,
      estoquesEspecificos:  estoquesEspecificosEnriquecidos,
      precoMediano:         mediana(precos),
      precoM2Mediano:       mediana(precosM2),
      custoUltimaCompra,
      custoM2UltimaCompra,
    };
  });
}

async function buscarPorId(id) {
  let m = await prisma.material.findUnique({
    where: { id },
    include: {
      fornecedorMateriais: {
        include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
      },
      historicoPrecos: {
        orderBy: { criadoEm: 'desc' },
        take: 50,
        include: {
          fornecedor:  { select: { id: true, nomeFantasia: true } },
          ordemCompra: { select: { id: true, data: true } },
        },
      },
      // ▼ NOVO
      estoquesEspecificos: {
        orderBy: { descricao: 'asc' },
      },
    },
  });

  if (!m) return null;

  // Enriquece filhos com o último preço de ENTRADA por descricaoItem
  if (m.especifico && m.estoquesEspecificos?.length) {
    const ultimasMovs = await prisma.movimentacaoEstoque.findMany({
      where: {
        materialId:    m.id,
        tipo:          'ENTRADA',
        descricaoItem: { not: null },
        OR: [
          { precoUnitario: { not: null } },
          { precoM2:       { not: null } },
        ],
      },
      orderBy: { criadoEm: 'desc' },
      select: {
        descricaoItem: true,
        precoUnitario: true,
        precoM2:       true,
      },
    });

    const precoMap = new Map();
    for (const mov of ultimasMovs) {
      if (!precoMap.has(mov.descricaoItem)) {
        precoMap.set(mov.descricaoItem, {
          ultimoValorPago:   mov.precoUnitario != null ? Number(mov.precoUnitario) : null,
          ultimoValorPagoM2: mov.precoM2       != null ? Number(mov.precoM2)       : null,
        });
      }
    }

    m = {
      ...m,
      estoquesEspecificos: m.estoquesEspecificos.map((filho) => ({
        ...filho,
        ...(precoMap.get(filho.descricao) ?? { ultimoValorPago: null, ultimoValorPagoM2: null }),
      })),
    };
  }

  return {
    ...m,
    custoUltimaCompra:   _normalizarPreco(m.ultimoValorPago),
    custoM2UltimaCompra: _normalizarPreco(m.ultimoValorPagoM2),
  };
}

async function criar(data) {
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
  data.especifico = data.especifico === true;

  data.ultimoValorPago   = _normalizarPreco(data.ultimoValorPago);
  data.ultimoValorPagoM2 = _normalizarPreco(data.ultimoValorPagoM2);

  try {
    return await prisma.material.create({ data: { ...data, status } });
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function atualizar(id, data) {
  const atual = await prisma.material.findUnique({ where: { id } });

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

  const quantidade    = data.quantidade    ?? atual.quantidade;
  const estoqueMinimo = data.estoqueMinimo ?? atual.estoqueMinimo;
  const ativo         = data.ativo         ?? atual.ativo;
  const status = calcularStatus(quantidade, estoqueMinimo, ativo);

  if (data.ultimoValorPago !== undefined) {
    data.ultimoValorPago = _normalizarPreco(data.ultimoValorPago);
  }
  if (data.ultimoValorPagoM2 !== undefined) {
    data.ultimoValorPagoM2 = _normalizarPreco(data.ultimoValorPagoM2);
  }

  try {
    return await prisma.material.update({ where: { id }, data: { ...data, status } });
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function desativar(id) {
  const material = await prisma.material.findUnique({
    where: { id },
    include: {
      _count: {
        select: {
          ordemItens: {
            where: { ordemCompra: { status: 'EM_ANDAMENTO' } },
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

async function listarHistoricoPrecos(materialId, limite = 50) {
  return prisma.historicoPrecoMaterial.findMany({
    where:   { materialId: Number(materialId) },
    orderBy: { criadoEm: 'desc' },
    take:    limite,
    include: {
      fornecedor:  { select: { id: true, nomeFantasia: true } },
      ordemCompra: { select: { id: true, data: true } },
    },
  });
}

async function excluirFilhoEspecifico(materialId, filhoId) {
  const filho = await prisma.estoqueEspecifico.findUnique({ where: { id: filhoId } });
  if (!filho || filho.materialId !== materialId) {
    throw { status: 404, message: 'Variação não encontrada' };
  }
  await prisma.estoqueEspecifico.delete({ where: { id: filhoId } });
}

async function atualizarFilhoEspecifico(materialId, filhoId, data) {
  const filho = await prisma.estoqueEspecifico.findUnique({ where: { id: filhoId } });
  if (!filho || filho.materialId !== materialId) {
    throw { status: 404, message: 'Variação não encontrada' };
  }

  // Verifica duplicidade de descrição (se mudou)
  const novaDesc = data.descricao?.trim();
  if (novaDesc && novaDesc !== filho.descricao) {
    const duplicado = await prisma.estoqueEspecifico.findUnique({
      where: { materialId_descricao: { materialId, descricao: novaDesc } },
    });
    if (duplicado) throw { status: 409, message: `Já existe uma variação com a descrição "${novaDesc}"` };
  }

  const updateData = {};
  if (novaDesc) updateData.descricao = novaDesc;
    if (data.quantidade !== undefined) {
    const novaQtd = Number(data.quantidade);
    if (isNaN(novaQtd) || novaQtd < 0) {
      throw { status: 400, message: 'Quantidade inválida' };
    }
    updateData.quantidade = novaQtd;
  }

  return prisma.estoqueEspecifico.update({
    where: { id: filhoId },
    data:  updateData,
  });
}

module.exports = {
  calcularStatus,
  listar,
  buscarPorId,
  criar,
  atualizar,
  desativar,
  reativar,
  excluir,
  confirmarEstoque,
  listarCategorias,
  listarHistoricoPrecos,
  atualizarFilhoEspecifico,
  excluirFilhoEspecifico,
};