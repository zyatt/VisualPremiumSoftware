const prisma = require('../utils/prisma');

function _calcularPrecoMedio(fornecedorMateriais, material = {}) {
  const refL = material.largura     != null ? Number(material.largura)     : null;
  const refC = material.comprimento != null ? Number(material.comprimento) : null;
  const area = (refL && refC && refL > 0 && refC > 0) ? refL * refC : null;

  const precos = fornecedorMateriais.map((fm) => Number(fm.preco)).filter((p) => p > 0);

  const precosM2 = fornecedorMateriais.map((fm) => {
    const direto = Number(fm.precoMetroQuadrado);
    if (direto > 0) return direto;
    const base = Number(fm.preco);
    if (base > 0 && area) return base / area;
    return 0;
  }).filter((p) => p > 0);

  const precosUnidadeMedida = fornecedorMateriais.map((fm) => {
    const direto = Number(fm.precoUnidadeMedida);
    if (direto > 0) return direto;
    const base = Number(fm.preco);
    if (base > 0 && refC && refC > 0) return base / refC;
    return 0;
  }).filter((p) => p > 0);

  const media = (arr) => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null;
  return {
    precoMedio: media(precos),
    precoMedioM2: media(precosM2),
    precoUnidadeMedidaMediano: media(precosUnidadeMedida),
  };
}

function _enrichMaterial(mat) {
  const { precoMedio, precoMedioM2, precoUnidadeMedidaMediano } =
      _calcularPrecoMedio(mat.fornecedorMateriais ?? [], mat);
  return {
    id:                mat.id,
    nome:              mat.nome,
    unidade:           mat.unidade,
    categoria:         mat.categoria,
    medida:            mat.medida,
    espessura:         mat.espessura,
    identificador:     mat.identificador,
    ultimoValorPago:   mat.ultimoValorPago   != null ? Number(mat.ultimoValorPago)   : null,
    ultimoValorPagoM2: mat.ultimoValorPagoM2 != null ? Number(mat.ultimoValorPagoM2) : null,
    largura:     mat.largura     != null ? Number(mat.largura)     : null,
    comprimento: mat.comprimento != null ? Number(mat.comprimento) : null,
    precoMedio,
    precoMedioM2,
    precoUnidadeMedidaMediano,
  };
}

function _serializarProduto(p) {
  return {
    ...p,
    materiais: p.materiais.map((pm) => ({
      id:         pm.id,
      produtoId:  pm.produtoId,
      materialId: pm.materialId,
      quantidade: Number(pm.quantidade),
      observacao: pm.observacao,
      material:   _enrichMaterial(pm.material),
    })),
  };
}

async function listar(filtros = {}) {
  const { busca, categoria, ativo } = filtros;
  const where = {};
  if (ativo === 'false') where.ativo = false;
  else if (ativo === 'true') where.ativo = true;
  if (busca) where.nome = { contains: busca, mode: 'insensitive' };
  if (categoria) where.categoria = { equals: categoria, mode: 'insensitive' };

  const produtos = await prisma.produto.findMany({
    where,
    include: {
      materiais: {
        include: {
          material: {
            include: {
              fornecedorMateriais: { where: { ativo: true } },
            },
          },
        },
        orderBy: { id: 'asc' },
      },
    },
    orderBy: [{ ativo: 'desc' }, { nome: 'asc' }],
  });

  return produtos.map(_serializarProduto);
}

async function buscarPorId(id) {
  const p = await prisma.produto.findUnique({
    where: { id },
    include: {
      materiais: {
        include: {
          material: {
            include: {
              fornecedorMateriais: { where: { ativo: true } },
            },
          },
        },
        orderBy: { id: 'asc' },
      },
    },
  });
  if (!p) throw { status: 404, message: 'Produto não encontrado' };
  return _serializarProduto(p);
}

async function criar(data) {
  const { nome, descricao, categoria, materiais = [] } = data;
  if (!nome?.trim()) throw { status: 400, message: 'Nome é obrigatório' };

  return prisma.produto.create({
    data: {
      nome:      nome.trim(),
      descricao: descricao?.trim() ?? null,
      categoria: categoria?.trim() ?? null,
      materiais: {
        create: materiais.map((m) => ({
          materialId: Number(m.materialId),
          quantidade: Number(m.quantidade) || 1,
          observacao: m.observacao ?? null,
        })),
      },
    },
    include: {
      materiais: {
        include: {
          material: { include: { fornecedorMateriais: { where: { ativo: true } } } },
        },
      },
    },
  }).then(_serializarProduto);
}

async function atualizar(id, data) {
  const { nome, descricao, categoria, materiais } = data;
  const produto = await prisma.produto.findUnique({ where: { id } });
  if (!produto) throw { status: 404, message: 'Produto não encontrado' };

  const updateData = {};
  if (nome      !== undefined) updateData.nome      = nome.trim();
  if (descricao !== undefined) updateData.descricao = descricao?.trim() ?? null;
  if (categoria !== undefined) updateData.categoria = categoria?.trim() ?? null;

  if (Array.isArray(materiais)) {
    await prisma.produtoMaterial.deleteMany({ where: { produtoId: id } });
    updateData.materiais = {
      create: materiais.map((m) => ({
        materialId: Number(m.materialId),
        quantidade: Number(m.quantidade) || 1,
        observacao: m.observacao ?? null,
      })),
    };
  }

  return prisma.produto.update({
    where: { id },
    data:  updateData,
    include: {
      materiais: {
        include: {
          material: { include: { fornecedorMateriais: { where: { ativo: true } } } },
        },
      },
    },
  }).then(_serializarProduto);
}

async function desativar(id) {
  const produto = await prisma.produto.findUnique({ where: { id } });
  if (!produto) throw { status: 404, message: 'Produto não encontrado' };
  return prisma.produto.update({ where: { id }, data: { ativo: false } });
}

async function reativar(id) {
  const produto = await prisma.produto.findUnique({ where: { id } });
  if (!produto) throw { status: 404, message: 'Produto não encontrado' };
  return prisma.produto.update({ where: { id }, data: { ativo: true } });
}

async function excluir(id) {
  const produto = await prisma.produto.findUnique({ where: { id } });
  if (!produto) throw { status: 404, message: 'Produto não encontrado' };
  if (produto.ativo) throw { status: 400, message: 'Desative o produto antes de excluí-lo' };
  return prisma.produto.delete({ where: { id } });
}

async function adicionarMaterial(produtoId, data) {
  const { materialId, quantidade, observacao } = data;
  if (!materialId) throw { status: 400, message: 'materialId é obrigatório' };

  const existe = await prisma.produtoMaterial.findUnique({
    where: { produtoId_materialId: { produtoId, materialId: Number(materialId) } },
  });
  if (existe) throw { status: 409, message: 'Material já vinculado a este produto' };

  return prisma.produtoMaterial.create({
    data: {
      produtoId,
      materialId: Number(materialId),
      quantidade: Number(quantidade) || 1,
      observacao: observacao ?? null,
    },
    include: {
      material: { include: { fornecedorMateriais: { where: { ativo: true } } } },
    },
  });
}

async function atualizarMaterial(produtoId, materialItemId, data) {
  const pm = await prisma.produtoMaterial.findUnique({ where: { id: materialItemId } });
  if (!pm || pm.produtoId !== produtoId) throw { status: 404, message: 'Vínculo não encontrado' };

  const updateData = {};
  if (data.quantidade !== undefined) updateData.quantidade = Number(data.quantidade);
  if (data.observacao !== undefined) updateData.observacao = data.observacao ?? null;

  return prisma.produtoMaterial.update({ where: { id: materialItemId }, data: updateData });
}

async function removerMaterial(produtoId, materialItemId) {
  const pm = await prisma.produtoMaterial.findUnique({ where: { id: materialItemId } });
  if (!pm || pm.produtoId !== produtoId) throw { status: 404, message: 'Vínculo não encontrado' };
  await prisma.produtoMaterial.delete({ where: { id: materialItemId } });
}

async function listarCategorias() {
  const result = await prisma.produto.findMany({
    where: { ativo: true, categoria: { not: null } },
    select: { categoria: true },
    distinct: ['categoria'],
    orderBy: { categoria: 'asc' },
  });
  return result.map((r) => r.categoria);
}

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  desativar,
  reativar,
  excluir,
  adicionarMaterial,
  atualizarMaterial,
  removerMaterial,
  listarCategorias,
};