const prisma = require('../utils/prisma');
const cfgSvc = require('./configuracao.service');

// ── helpers ───────────────────────────────────────────────────────────────────

function _calcularPrecoMedio(fornecedorMateriais = []) {
  const precos   = fornecedorMateriais.map((fm) => Number(fm.preco)).filter((p) => p > 0);
  const precosM2 = fornecedorMateriais.map((fm) => Number(fm.precoMetroQuadrado)).filter((p) => p > 0);
  const media    = (arr) => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null;
  return { precoMedio: media(precos), precoMedioM2: media(precosM2) };
}

/**
 * Calcula a área de sobra (m²) e custo de desperdício para um item de material.
 * Retorna { areaSobraM2, custoSobra } — ambos null quando não aplicável.
 */
function _calcularSobra(m, custoPorM2) {
  const refL = m.material.largura    != null ? Number(m.material.largura)    : null;
  const refC = m.material.comprimento != null ? Number(m.material.comprimento) : null;
  if (!refL || !refC || refL <= 0 || refC <= 0) return { areaSobraM2: null, custoSobra: null };

  const l = m.largura    != null ? Number(m.largura)    : null;
  const c = m.comprimento != null ? Number(m.comprimento) : null;
  if (!l || !c || l <= 0 || c <= 0) return { areaSobraM2: null, custoSobra: null };

  const areaRef    = refL * refC;
  const areaCortada = l * c;
  if (areaCortada >= areaRef) return { areaSobraM2: null, custoSobra: null };

  const areaSobraM2 = areaRef - areaCortada;
  const custoSobra  = custoPorM2 != null ? areaSobraM2 * custoPorM2 * Number(m.quantidade) : null;
  return { areaSobraM2, custoSobra };
}

function _serializarItem(item) {
  return {
    id:         item.id,
    produtoId:  item.produtoId,
    quantidade: Number(item.quantidade),
    observacao: item.observacao,
    produto: {
      id:        item.produto.id,
      nome:      item.produto.nome,
      descricao: item.produto.descricao,
      categoria: item.produto.categoria,
    },
    materiais: item.materiais.map((m) => {
      const { precoMedio, precoMedioM2 } = _calcularPrecoMedio(
        m.material.fornecedorMateriais ?? [],
      );
      // Custo por m² da chapa de referência
      const refL = m.material.largura     != null ? Number(m.material.largura)     : null;
      const refC = m.material.comprimento != null ? Number(m.material.comprimento)  : null;
      const custoChapa = m.material.ultimoValorPago != null
        ? Number(m.material.ultimoValorPago)
        : (precoMedio ?? null);
      const custoPorM2 = (refL && refC && refL > 0 && refC > 0 && custoChapa)
        ? custoChapa / (refL * refC)
        : null;
      const { areaSobraM2, custoSobra } = _calcularSobra(m, custoPorM2);
      return {
        id:           m.id,
        materialId:   m.materialId,
        quantidade:   Number(m.quantidade),
        precoMedio:   m.precoMedio   != null ? Number(m.precoMedio)   : precoMedio,
        precoMedioM2: m.precoMedioM2 != null ? Number(m.precoMedioM2) : precoMedioM2,
        precoUnitario: m.precoUnitario != null ? Number(m.precoUnitario) : null,
        largura:      m.largura      != null ? Number(m.largura)      : null,
        comprimento:  m.comprimento  != null ? Number(m.comprimento)  : null,
        usarM2:       m.usarM2,
        areaSobraM2:  areaSobraM2,
        custoSobra:   custoSobra,
        material: {
          id:                m.material.id,
          nome:              m.material.nome,
          unidade:           m.material.unidade,
          categoria:         m.material.categoria,
          medida:            m.material.medida,
          espessura:         m.material.espessura,
          identificador:     m.material.identificador,
          ultimoValorPago:   m.material.ultimoValorPago   != null ? Number(m.material.ultimoValorPago)   : null,
          ultimoValorPagoM2: m.material.ultimoValorPagoM2 != null ? Number(m.material.ultimoValorPagoM2) : null,
          largura:           m.material.largura    != null ? Number(m.material.largura)    : null,
          comprimento:       m.material.comprimento != null ? Number(m.material.comprimento) : null,
          precoMedio,
          precoMedioM2,
        },
      };
    }),
  };
}

/**
 * Serializa o orçamento — agora async para buscar o percentualMarkup das faixas.
 */
async function _serializarOrcamento(ov) {
  const { custoBase, custoSobraTotal } = _decomporCustos(ov);
  const total = custoBase + custoSobraTotal;

  let percentualMarkup = 0;
  try {
    const params = await cfgSvc.obterParametros(total);
    percentualMarkup = params.percentualMarkup ?? 0;
  } catch (_) {}

  return {
    id:               ov.id,
    numero:           ov.numero,
    status:           ov.status,
    observacao:       ov.observacao,
    valorTotal:       Number(ov.valorTotal),
    custoBase:        custoBase,
    custoSobra:       custoSobraTotal,
    percentualMarkup: percentualMarkup,
    margemLucro:      ov.margemLucro != null ? Number(ov.margemLucro) : null,
    criadoEm:         ov.criadoEm,
    atualizadoEm:     ov.atualizadoEm,
    clienteNome:      ov.clienteNome,
    cliente: ov.cliente ? { id: ov.cliente.id, nome: ov.cliente.nome } : null,
    criador: ov.criador ? { id: ov.criador.id, nome: ov.criador.nome } : null,
    itens: (ov.itens ?? []).map(_serializarItem),
  };
}

/** Gera próximo número "OV-YYYY-NNNN". */
async function _gerarNumero() {
  const ano  = new Date().getFullYear();
  const prefixo = `OV-${ano}-`;
  const ultimo = await prisma.orcamentoVenda.findFirst({
    where:   { numero: { startsWith: prefixo } },
    orderBy: { numero: 'desc' },
    select:  { numero: true },
  });
  const seq = ultimo
    ? parseInt(ultimo.numero.replace(prefixo, ''), 10) + 1
    : 1;
  return `${prefixo}${String(seq).padStart(4, '0')}`;
}

/** Include padrão para buscar orçamento completo. */
const _include = {
  cliente: true,
  criador: true,
  itens: {
    include: {
      produto: true,
      materiais: {
        include: {
          material: {
            include: { fornecedorMateriais: { where: { ativo: true } } },
          },
        },
      },
    },
    orderBy: { id: 'asc' },
  },
};

// ── CRUD OrcamentoVenda ───────────────────────────────────────────────────────

async function listar(filtros = {}) {
  const { status, clienteId, busca } = filtros;
  const where = {};
  if (status)    where.status    = status;
  if (clienteId) where.clienteId = Number(clienteId);
  if (busca)     where.numero    = { contains: busca, mode: 'insensitive' };

  const lista = await prisma.orcamentoVenda.findMany({
    where,
    include: _include,
    orderBy: [{ status: 'asc' }, { criadoEm: 'desc' }],
  });
  return Promise.all(lista.map(_serializarOrcamento));
}

async function buscarPorId(id) {
  const ov = await prisma.orcamentoVenda.findUnique({ where: { id }, include: _include });
  if (!ov) throw { status: 404, message: 'Orçamento não encontrado' };
  return await _serializarOrcamento(ov);
}

/**
 * Cria um orçamento de venda.
 * Body esperado:
 * {
 *   clienteNome: string,
 *   numero?: string,
 *   observacao?: string,
 *   margemLucro?: number,
 *   criadorId?: number,
 *   clienteId?: number,
 *   itens: [
 *     {
 *       produtoId: number,
 *       quantidade: number,
 *       observacao?: string,
 *       materiais: [
 *         { materialId, quantidade, precoUnitario?, usarM2? }
 *       ]
 *     }
 *   ]
 * }
 */
async function criar(data) {
  const {
    numero: numeroCustom,
    clienteId,
    clienteNome,
    criadorId,
    observacao,
    margemLucro,
    itens = [],
  } = data;

  const numero = numeroCustom?.trim() || (await _gerarNumero());

  if (await prisma.orcamentoVenda.findUnique({ where: { numero } })) {
    throw { status: 409, message: `Número de orçamento "${numero}" já existe` };
  }

  const ov = await prisma.orcamentoVenda.create({
    data: {
      numero,
      clienteNome: clienteNome?.trim() || null,
      observacao:  observacao?.trim() ?? null,
      margemLucro: margemLucro != null ? Number(margemLucro) : null,
      ...(criadorId ? { criador: { connect: { id: Number(criadorId) } } } : {}),
      ...(clienteId ? { cliente: { connect: { id: Number(clienteId) } } } : {}),
      itens: itens.length > 0 ? { create: itens.map(_buildItemCreate) } : undefined,
    },
    include: _include,
  });

  // Calcula e persiste valorTotal (com markup + imposto sobre sobra)
  const valorTotal = await _calcularTotalFinal(ov);
  const atualizado = await prisma.orcamentoVenda.update({
    where:   { id: ov.id },
    data:    { valorTotal },
    include: _include,
  });
  return await _serializarOrcamento(atualizado);
}

async function atualizar(id, data) {
  const ov = await prisma.orcamentoVenda.findUnique({ where: { id } });
  if (!ov) throw { status: 404, message: 'Orçamento não encontrado' };

  const { observacao, margemLucro, status, itens } = data;
  const updateData = {};
  if (observacao  !== undefined) updateData.observacao  = observacao?.trim() ?? null;
  if (margemLucro !== undefined) updateData.margemLucro = Number(margemLucro);
  if (status      !== undefined) updateData.status      = status;

  if (Array.isArray(itens)) {
    await prisma.orcamentoVendaItem.deleteMany({ where: { orcamentoVendaId: id } });
    updateData.itens = { create: itens.map(_buildItemCreate) };
  }

  const atualizado = await prisma.orcamentoVenda.update({
    where:   { id },
    data:    updateData,
    include: _include,
  });

  const valorTotal = await _calcularTotalFinal(atualizado);
  const final_ = await prisma.orcamentoVenda.update({
    where:   { id },
    data:    { valorTotal },
    include: _include,
  });
  return await _serializarOrcamento(final_);
}

async function excluir(id) {
  const ov = await prisma.orcamentoVenda.findUnique({ where: { id } });
  if (!ov) throw { status: 404, message: 'Orçamento não encontrado' };
  await prisma.orcamentoVenda.delete({ where: { id } });
}

async function alterarStatus(id, novoStatus) {
  const ov = await prisma.orcamentoVenda.findUnique({ where: { id } });
  if (!ov) throw { status: 404, message: 'Orçamento não encontrado' };
  return prisma.orcamentoVenda.update({
    where: { id },
    data:  { status: novoStatus },
  });
}

// ── Gerenciar itens ───────────────────────────────────────────────────────────

async function adicionarItem(orcamentoVendaId, data) {
  const ov = await prisma.orcamentoVenda.findUnique({ where: { id: orcamentoVendaId } });
  if (!ov) throw { status: 404, message: 'Orçamento não encontrado' };

  const item = await prisma.orcamentoVendaItem.create({
    data: {
      orcamentoVendaId,
      ..._buildItemCreate(data),
    },
    include: {
      produto: true,
      materiais: {
        include: {
          material: { include: { fornecedorMateriais: { where: { ativo: true } } } },
        },
      },
    },
  });

  await _recalcularTotal(orcamentoVendaId);
  return _serializarItem(item);
}

async function atualizarItem(orcamentoVendaId, itemId, data) {
  const item = await prisma.orcamentoVendaItem.findUnique({ where: { id: itemId } });
  if (!item || item.orcamentoVendaId !== orcamentoVendaId)
    throw { status: 404, message: 'Item não encontrado' };

  const { quantidade, observacao, materiais } = data;
  const upd = {};
  if (quantidade !== undefined) upd.quantidade = Number(quantidade);
  if (observacao !== undefined) upd.observacao = observacao ?? null;

  if (Array.isArray(materiais)) {
    await prisma.orcamentoVendaItemMaterial.deleteMany({ where: { orcamentoVendaItemId: itemId } });
    upd.materiais = { create: materiais.map(_buildMaterialCreate) };
  }

  const atualizado = await prisma.orcamentoVendaItem.update({
    where:   { id: itemId },
    data:    upd,
    include: {
      produto: true,
      materiais: {
        include: {
          material: { include: { fornecedorMateriais: { where: { ativo: true } } } },
        },
      },
    },
  });

  await _recalcularTotal(orcamentoVendaId);
  return _serializarItem(atualizado);
}

async function removerItem(orcamentoVendaId, itemId) {
  const item = await prisma.orcamentoVendaItem.findUnique({ where: { id: itemId } });
  if (!item || item.orcamentoVendaId !== orcamentoVendaId)
    throw { status: 404, message: 'Item não encontrado' };
  await prisma.orcamentoVendaItem.delete({ where: { id: itemId } });
  await _recalcularTotal(orcamentoVendaId);
}

// ── Helpers internos ──────────────────────────────────────────────────────────

function _buildMaterialCreate(m) {
  return {
    materialId:    Number(m.materialId),
    quantidade:    Number(m.quantidade) || 0,
    precoUnitario: m.precoUnitario != null ? Number(m.precoUnitario) : null,
    precoMedio:    m.precoMedio    != null ? Number(m.precoMedio)    : null,
    precoMedioM2:  m.precoMedioM2  != null ? Number(m.precoMedioM2) : null,
    largura:       m.largura       != null ? Number(m.largura)       : null,
    comprimento:   m.comprimento   != null ? Number(m.comprimento)   : null,
    usarM2:        m.usarM2        ?? false,
  };
}

function _buildItemCreate(item) {
  return {
    produtoId:  Number(item.produtoId),
    quantidade: Number(item.quantidade) || 1,
    observacao: item.observacao ?? null,
    materiais: {
      create: (item.materiais ?? []).map(_buildMaterialCreate),
    },
  };
}

/**
 * Retorna { custoBase, custoSobraTotal } separados.
 */
function _decomporCustos(ov) {
  let custoBase = 0;
  let custoSobraTotal = 0;

  for (const item of ov.itens ?? []) {
    for (const m of item.materiais ?? []) {
      const preco = m.precoUnitario != null
        ? Number(m.precoUnitario)
        : (m.precoMedio != null ? Number(m.precoMedio) : 0);
      custoBase += Number(m.quantidade) * preco;

      const refL = m.material?.largura     != null ? Number(m.material.largura)     : null;
      const refC = m.material?.comprimento != null ? Number(m.material.comprimento)  : null;
      const custoChapa = m.material?.ultimoValorPago != null
        ? Number(m.material.ultimoValorPago)
        : (m.precoMedio != null ? Number(m.precoMedio) : null);
      if (refL && refC && refL > 0 && refC > 0 && custoChapa && m.largura != null && m.comprimento != null) {
        const custoPorM2  = custoChapa / (refL * refC);
        const areaRef     = refL * refC;
        const areaCortada = Number(m.largura) * Number(m.comprimento);
        if (areaCortada < areaRef) {
          custoSobraTotal += (areaRef - areaCortada) * custoPorM2 * Number(m.quantidade);
        }
      }
    }
  }
  return { custoBase, custoSobraTotal };
}

// Mantido para compatibilidade interna (não aplica markup)
function _calcularTotal(ov) {
  const { custoBase, custoSobraTotal } = _decomporCustos(ov);
  return custoBase + custoSobraTotal;
}

/**
 * Calcula o valorTotal final com markup e imposto sobre sobra aplicados.
 */
async function _calcularTotalFinal(ov) {
  const { custoBase, custoSobraTotal } = _decomporCustos(ov);
  const total = custoBase + custoSobraTotal;

  try {
    const { percentualMarkup, impostoSobra } = await cfgSvc.obterParametros(total);
    const baseComMarkup   = custoBase       * (1 + percentualMarkup / 100);
    const sobraComImposto = custoSobraTotal * (1 + impostoSobra     / 100);
    return baseComMarkup + sobraComImposto;
  } catch (_) {
    return total;
  }
}

async function _recalcularTotal(orcamentoVendaId) {
  const ov = await prisma.orcamentoVenda.findUnique({
    where: { id: orcamentoVendaId },
    include: {
      itens: {
        include: {
          materiais: {
            // Inclui todos os campos do OrcamentoVendaItemMaterial usados em _decomporCustos
            include: {
              material: {
                select: {
                  largura:         true,
                  comprimento:     true,
                  ultimoValorPago: true,
                },
              },
            },
          },
        },
      },
    },
  });
  if (!ov) return;
  const valorTotal = await _calcularTotalFinal(ov);
  await prisma.orcamentoVenda.update({ where: { id: orcamentoVendaId }, data: { valorTotal } });
}

// ── Clientes (lookup rápido) ──────────────────────────────────────────────────

async function listarClientes(busca) {
  const where = busca
    ? { nome: { contains: busca, mode: 'insensitive' } }
    : {};
  const clientes = await prisma.cliente.findMany({
    where,
    select:  { id: true, nome: true },
    orderBy: { nome: 'asc' },
    take:    50,
  });
  return clientes;
}

module.exports = {
  listar,
  buscarPorId,
  criar,
  atualizar,
  excluir,
  alterarStatus,
  adicionarItem,
  atualizarItem,
  removerItem,
  listarClientes,
};