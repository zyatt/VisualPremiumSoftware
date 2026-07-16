const prisma = require('../utils/prisma');
const auditSvc = require('./audit-log.service');

const _sseClients = new Map();
let _nextSseId = 1;

function registrarSseCliente(res, usuarioId) {
  const id = _nextSseId++;
  _sseClients.set(id, { res, usuarioId });
  console.log(`[SSE Materiais] Cliente ${usuarioId} conectado (total: ${_sseClients.size})`);
  try {
    res.write(`data: ${JSON.stringify({ tipo: 'conectado', usuarioId })}\n\n`);
  } catch (err) {
    console.error(`[SSE Materiais] Erro ao enviar confirmação: ${err.message}`);
  }
  return () => {
    _sseClients.delete(id);
    console.log(`[SSE Materiais] Cliente ${usuarioId} desconectado (total: ${_sseClients.size})`);
  };
}

function _broadcast(tipo, dados, excludeUsuarioId) {
  const payload = `data: ${JSON.stringify({ tipo, ...dados })}\n\n`;
  let enviados = 0;
  for (const { res, usuarioId } of _sseClients.values()) {
    if (excludeUsuarioId !== undefined && usuarioId === excludeUsuarioId) continue;
    try { res.write(payload); enviados++; }
    catch (err) { console.error(`[SSE Materiais] Erro para usuário ${usuarioId}: ${err.message}`); }
  }
  console.log(`[SSE Materiais] Evento '${tipo}' enviado para ${enviados} cliente(s)`);
}

function calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _broadcastCritico(material) {
  _broadcast('material_critico', {
    materialId:    material.id,
    nome:          material.nome,
    identificador: material.identificador,
    medida:        material.medida,
    espessura:     material.espessura,
    unidade:       material.unidade,
    categoria:     material.categoria,
    quantidade:    Number(material.quantidade),
    estoqueMinimo: Number(material.estoqueMinimo),
  });
}

function notificarSeCritico(statusAntes, materialDepois) {
  if (statusAntes !== 'CRITICO' && materialDepois.status === 'CRITICO') {
    _broadcastCritico(materialDepois);
  }
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

function _mapearMaterial(m) {
  const precos = m.fornecedorMateriais
    .map((fm) => Number(fm.preco))
    .filter((p) => p > 0)
    .sort((a, b) => a - b);

  const precosM2 = m.fornecedorMateriais
    .map((fm) => Number(fm.precoMetroQuadrado))
    .filter((p) => p > 0)
    .sort((a, b) => a - b);

  const media = (arr) => {
    if (!arr.length) return null;
    return arr.reduce((a, b) => a + b, 0) / arr.length;
  };

  return {
    ...m,
    precoMediano:         media(precos),
    precoM2Mediano:       media(precosM2),
    custoUltimaCompra:    _normalizarPreco(m.ultimoValorPago),
    custoM2UltimaCompra:  _normalizarPreco(m.ultimoValorPagoM2),
  };
}

const _includeFornecedores = {
  fornecedorMateriais: {
    where: { ativo: true },
    include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
  },
};

async function listar(filtros = {}) {
  const { busca, categoria, semCategoria, status, comFornecedor, id, medida, espessura, largura, comprimento, identificador, ativo } = filtros;

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
  if (largura !== undefined && largura !== '')     where.largura     = Number(largura);
  if (comprimento !== undefined && comprimento !== '') where.comprimento = Number(comprimento);
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
    include: _includeFornecedores,
    orderBy: [{ ativo: 'desc' }, { nome: 'asc' }],
  });

  return materiais.map(_mapearMaterial);
}

async function listarParaMovimentacao(filtros = {}) {
  return listar({ ...filtros, ativo: 'true' });
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
    },
  });

  if (!m) return null;

  return {
    ...m,
    custoUltimaCompra:   _normalizarPreco(m.ultimoValorPago),
    custoM2UltimaCompra: _normalizarPreco(m.ultimoValorPagoM2),
  };
}

async function criar(data, usuarioId, usuarioNome) {
  const nomeTrimmed      = data.nome?.trim();
  const medidaTrimmed    = data.medida?.trim()       ?? null;
  const espessuraTrimmed = data.espessura?.trim()    ?? null;

  const identificadorTrimmed = data.identificador?.trim() ?? null;
  const duplicado = await prisma.material.findFirst({
    where: {
      nome:         { equals: nomeTrimmed, mode: 'insensitive' },
      identificador: identificadorTrimmed
        ? { equals: identificadorTrimmed, mode: 'insensitive' }
        : null,
      medida:       medidaTrimmed    ? { equals: medidaTrimmed,    mode: 'insensitive' } : null,
      espessura:    espessuraTrimmed ? { equals: espessuraTrimmed, mode: 'insensitive' } : null,
    },
  });

  if (duplicado) _throwDuplicado(medidaTrimmed, espessuraTrimmed);

  const status = calcularStatus(data.quantidade || 0, data.estoqueMinimo || 0, true);
  data.ultimoValorPago   = _normalizarPreco(data.ultimoValorPago);
  data.ultimoValorPagoM2 = _normalizarPreco(data.ultimoValorPagoM2);

  try {
    const material = await prisma.material.create({ data: { ...data, status } });

    await auditSvc.registrar(material.id, 'CADASTRO', {
      valorDepois: material.nome,
      usuarioId,
      usuarioNome,
      material,
    });

    _broadcast('material_atualizado', {
      motivo: 'criar',
      materialId: material.id,
      nome: material.nome,
    }, usuarioId);

    return material;
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function atualizar(id, data, usuarioId, usuarioNome) {
  const atual = await prisma.material.findUnique({ where: { id } });

  const nomeTrimmed        = (data.nome        ?? atual.nome)?.trim();
  const medidaTrimmed      = (data.medida       ?? atual.medida)?.trim()       ?? null;
  const espessuraTrimmed   = (data.espessura    ?? atual.espessura)?.trim()    ?? null;

  const identificadorTrimmed = (data.identificador ?? atual.identificador)?.trim() ?? null;
  const duplicado = await prisma.material.findFirst({
    where: {
      id:           { not: id },
      nome:         { equals: nomeTrimmed, mode: 'insensitive' },
      identificador: identificadorTrimmed
        ? { equals: identificadorTrimmed, mode: 'insensitive' }
        : null,
      medida:       medidaTrimmed    ? { equals: medidaTrimmed,    mode: 'insensitive' } : null,
      espessura:    espessuraTrimmed ? { equals: espessuraTrimmed, mode: 'insensitive' } : null,
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

  const snapAntes = await prisma.material.findUnique({ where: { id } });

  try {
    const material = await prisma.material.update({ where: { id }, data: { ...data, status } });

    await auditSvc.registrarEdicao(id, snapAntes, material, usuarioId, usuarioNome);

    _broadcast('material_atualizado', {
      motivo: 'atualizar',
      materialId: material.id,
      nome: material.nome,
    }, usuarioId);

    notificarSeCritico(snapAntes.status, material);

    return material;
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function desativar(id, usuarioId, usuarioNome) {
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

  const result = await prisma.material.update({
    where: { id },
    data: { ativo: false, status: 'INATIVO' },
  });

  await auditSvc.registrar(id, 'DESATIVACAO', { usuarioId, usuarioNome, material: result });
  _broadcast('material_atualizado', { motivo: 'desativar', materialId: id }, usuarioId);
  return result;
}

async function reativar(id, usuarioId, usuarioNome) {
  const material = await prisma.material.findUnique({ where: { id } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  if (material.ativo) throw { status: 400, message: 'Material já está ativo' };

  const status = calcularStatus(material.quantidade, material.estoqueMinimo, true);

  const result = await prisma.material.update({
    where: { id },
    data: { ativo: true, status },
  });

  await auditSvc.registrar(id, 'REATIVACAO', { usuarioId, usuarioNome, material: result });
  _broadcast('material_atualizado', { motivo: 'reativar', materialId: id }, usuarioId);
  return result;
}

async function excluir(id, usuarioId, usuarioNome) {
  const material = await prisma.material.findUnique({ where: { id } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  if (material.ativo) throw { status: 400, message: 'Desative o material antes de excluí-lo' };

  // Orphaning de ordemItens antes do delete para evitar violação de FK.
  await prisma.ordemCompraItem.updateMany({
    where: { materialId: id },
    data: {
      materialId:    null,
      descricaoItem: material.nome,
    },
  });

  // Deleta PRIMEIRO. Com onDelete: SetNull no schema, o banco seta
  // materialId = NULL em todos os AuditLogMaterial existentes para este
  // material — preservando o histórico completo via snapshot (*Snap).
  // Se ainda houver FK com RESTRICT em outra tabela (ex.: movimentações),
  // o delete falha aqui antes de qualquer log ser gravado, mantendo
  // o estado do banco consistente.
  let deletado;
  try {
    deletado = await prisma.material.delete({ where: { id } });
  } catch (e) {
    if (e?.code === 'P2003') {
      throw {
        status: 400,
        message: 'Não é possível excluir: este material possui movimentações de estoque vinculadas. Desative-o em vez de excluir.',
      };
    }
    throw e;
  }

  // Grava o log de EXCLUSAO depois do delete. O materialId passado (id)
  // já não existe mais na tabela materiais, então o banco grava NULL
  // nesse campo (onDelete: SetNull), mas o snapshot capturado em `material`
  // acima preserva todos os dados descritivos para exibição no histórico.
  await auditSvc.registrar(id, 'EXCLUSAO', {
    valorAntes: material.nome,
    usuarioId,
    usuarioNome,
    material,
  });

  _broadcast('material_atualizado', { motivo: 'excluir', materialId: id }, usuarioId);
  return deletado;
}

async function confirmarEstoque(id, usuarioId, usuarioNome) {
  const result = await prisma.material.update({ where: { id }, data: { estoqueConfirmado: true } });

  await auditSvc.registrar(id, 'ESTOQUE_CONFIRMADO', { usuarioId, usuarioNome, material: result });
  _broadcast('material_atualizado', { motivo: 'confirmar', materialId: id }, usuarioId);
  return result;
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

async function atualizarCustoManual(id, data, usuarioId, usuarioNome) {
  const material = await prisma.material.findUnique({ where: { id } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };

  const novoUnitario = data.ultimoValorPago   != null ? _normalizarPreco(data.ultimoValorPago)   : undefined;
  const novoM2       = data.ultimoValorPagoM2 != null ? _normalizarPreco(data.ultimoValorPagoM2) : undefined;

  if (novoUnitario === undefined && novoM2 === undefined) {
    throw { status: 400, message: 'Informe ao menos um valor (unitário ou m²)' };
  }

  const updateData = {};
  if (novoUnitario !== undefined) updateData.ultimoValorPago   = novoUnitario;
  if (novoM2       !== undefined) updateData.ultimoValorPagoM2 = novoM2;

  const result = await prisma.material.update({ where: { id }, data: updateData });

  if (novoUnitario !== material.ultimoValorPago) {
    await auditSvc.registrar(id, 'CUSTO_MANUAL', {
      campo: 'Último Valor Pago',
      valorAntes:
        material.ultimoValorPago != null
          ? Number(material.ultimoValorPago).toFixed(2)
          : null,
      valorDepois:
        novoUnitario != null
          ? Number(novoUnitario).toFixed(2)
          : null,
      usuarioId,
      usuarioNome,
      material: result,
    });
  }

  if (novoM2 !== material.ultimoValorPagoM2) {
    await auditSvc.registrar(id, 'CUSTO_MANUAL', {
      campo: 'Último Valor Pago m²',
      valorAntes:
        material.ultimoValorPagoM2 != null
          ? Number(material.ultimoValorPagoM2).toFixed(2)
          : null,
      valorDepois:
        novoM2 != null
          ? Number(novoM2).toFixed(2)
          : null,
      usuarioId,
      usuarioNome,
      material: result,
    });
  }

  _broadcast('material_atualizado', { motivo: 'custo', materialId: id }, usuarioId);

  return {
    ...result,
    custoUltimaCompra:   _normalizarPreco(result.ultimoValorPago),
    custoM2UltimaCompra: _normalizarPreco(result.ultimoValorPagoM2),
  };
}

module.exports = {
  calcularStatus,
  notificarSeCritico,
  listar,
  listarParaMovimentacao,
  buscarPorId,
  criar,
  atualizar,
  desativar,
  reativar,
  excluir,
  confirmarEstoque,
  atualizarCustoManual,
  listarCategorias,
  listarHistoricoPrecos,
  registrarSseCliente,
};