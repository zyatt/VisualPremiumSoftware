const prisma = require('../utils/prisma');

const _LABELS = {
  nome:              'Nome',
  unidade:           'Unidade',
  categoria:         'Categoria',
  medida:            'Medida',
  espessura:         'Espessura',
  identificador:     'Identificador',
  largura:           'Largura (m)',
  comprimento:       'Comprimento (m)',
  valor:             'Valor',
  valorMetroQuadrado:'Valor m²',
  quantidade:        'Quantidade',
  estoqueMinimo:     'Estoque Mínimo',
  status:            'Status',
  ativo:             'Ativo',
  ultimoValorPago:   'Último Valor Pago',
  ultimoValorPagoM2: 'Último Valor Pago m²',

  // Fluxo de aprovação de cadastro (usuários não-ADMIN)
  estoqueConfirmado:   'Estoque Confirmado',
  aguardandoAprovacao: 'Aguardando Aprovação',
  criadoPorId:         'Cadastrado Por',
  criadoPorNome:       'Cadastrado Por',
  aprovadoPorId:       'Aprovado Por',
  aprovadoPorNome:     'Aprovado Por',
  aprovadoEm:          'Data de Aprovação',
};

const _IGNORAR = new Set([
  'criadoEm', 'atualizadoEm', 'id',
  // Preenchidos automaticamente pelo próprio fluxo de aprovação — não fazem
  // sentido como "campo alterado" dentro de uma EDICAO comum.
  'criadoPorId', 'aprovadoPorId', 'aprovadoEm',
]);

/// Converte um nome de campo cru (camelCase, ex: "custoM2UltimaCompra") em um
/// texto legível ("Custo M2 Ultima Compra") para exibição ao usuário, usado
/// como último recurso quando o campo não está mapeado em _LABELS. Isso
/// evita que o histórico mostre nomes de variável/método truncados.
function _labelFallback(campo) {
  if (!campo) return campo;
  const comEspacos = campo
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/_/g, ' ')
    .trim();
  return comEspacos.charAt(0).toUpperCase() + comEspacos.slice(1);
}

function _str(v) {
  if (v === null || v === undefined) return null;
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    const isDecimal =
      v.constructor?.name === 'Decimal' ||
      (typeof v.toFixed === 'function' && typeof v.isNaN === 'function') ||
      (Array.isArray(v.d) && typeof v.e === 'number');
    if (isDecimal) return v.toString();
    return null;
  }
  return String(v);
}

function _label(campo) {
  return _LABELS[campo] ?? _labelFallback(campo);
}

function _snapshot(material) {
  if (!material) return {};
  return {
    materialNomeSnap:          material.nome ?? null,
    materialCategoriaSnap:     material.categoria ?? null,
    materialUnidadeSnap:       material.unidade ?? null,
    materialMedidaSnap:        material.medida ?? null,
    materialEspessuraSnap:     material.espessura ?? null,
    materialIdentificadorSnap: material.identificador ?? null,
    materialLarguraSnap:       material.largura != null ? String(material.largura) : null,
    materialComprimentoSnap:   material.comprimento != null ? String(material.comprimento) : null,
  };
}

async function registrar(materialId, acao, opts = {}) {
  const { campo, valorAntes, valorDepois, usuarioId, usuarioNome, material } = opts;

  const materialExiste = materialId != null
    ? await prisma.material.findUnique({ where: { id: materialId }, select: { id: true } })
    : null;

  await prisma.auditLogMaterial.create({
    data: {
      materialId:  materialExiste ? materialId : null,
      acao,
      campo:       campo      ?? null,
      valorAntes:  _str(valorAntes),
      valorDepois: _str(valorDepois),
      usuarioId:   usuarioId  ?? null,
      usuarioNome: usuarioNome ?? null,
      ..._snapshot(material),
    },
  });
}

async function registrarEdicao(materialId, antes, depois, usuarioId, usuarioNome) {
  const campos = new Set([...Object.keys(antes), ...Object.keys(depois)]);
  const promessas = [];
  const snap = _snapshot(depois);

  for (const campo of campos) {
    if (_IGNORAR.has(campo)) continue;
    const vAntes  = _str(antes[campo]);
    const vDepois = _str(depois[campo]);
    if (vAntes === vDepois) continue;

    promessas.push(
      prisma.auditLogMaterial.create({
        data: {
          materialId,
          acao:        'EDICAO',
          campo:       _label(campo),
          valorAntes:  vAntes,
          valorDepois: vDepois,
          usuarioId:   usuarioId  ?? null,
          usuarioNome: usuarioNome ?? null,
          ...snap,
        },
      })
    );
  }

  if (promessas.length > 0) await Promise.all(promessas);
}

const _MATERIAL_SELECT = {
  id: true, nome: true, categoria: true, unidade: true,
  medida: true, espessura: true, identificador: true,
  largura: true, comprimento: true, descricao: true,
};

function _comMaterialResolvido(log) {
  const { materialNomeSnap, materialCategoriaSnap, materialUnidadeSnap,
          materialMedidaSnap, materialEspessuraSnap, materialIdentificadorSnap,
          materialLarguraSnap, materialComprimentoSnap, ...resto } = log;

  const material = log.material ?? {
    id:            log.materialId,
    nome:          materialNomeSnap,
    categoria:     materialCategoriaSnap,
    unidade:       materialUnidadeSnap,
    medida:        materialMedidaSnap,
    espessura:     materialEspessuraSnap,
    identificador: materialIdentificadorSnap,
    largura:       materialLarguraSnap,
    comprimento:   materialComprimentoSnap,
  };

  return { ...resto, material, materialExcluido: log.material == null };
}

async function listarPorMaterial(materialId, limite = 200) {
  const logs = await prisma.auditLogMaterial.findMany({
    where:   { materialId: Number(materialId) },
    orderBy: { criadoEm: 'desc' },
    take:    limite,
    include: { material: { select: _MATERIAL_SELECT } },
  });
  return logs.map(_comMaterialResolvido);
}

async function listar(filtros = {}) {
  const {
    materialId, acao, usuarioId,
    dataInicio, dataFim, busca,
    limite = 500,
  } = filtros;

  const where = {};

  if (materialId) where.materialId = Number(materialId);
  if (acao)       where.acao       = acao;
  if (usuarioId)  where.usuarioId  = Number(usuarioId);

  if (dataInicio || dataFim) {
    where.criadoEm = {};
    if (dataInicio) where.criadoEm.gte = new Date(dataInicio);
    if (dataFim) {
      const fim = new Date(dataFim);
      fim.setHours(23, 59, 59, 999);
      where.criadoEm.lte = fim;
    }
  }

  if (busca) {
    where.OR = [
      { material:        { nome: { contains: busca, mode: 'insensitive' } } },
      { materialNomeSnap: { contains: busca, mode: 'insensitive' } },
    ];
  }

  const logs = await prisma.auditLogMaterial.findMany({
    where,
    orderBy: { criadoEm: 'desc' },
    take:    Number(limite),
    include: {
      material: { select: _MATERIAL_SELECT },
    },
  });
  return logs.map(_comMaterialResolvido);
}

module.exports = { registrar, registrarEdicao, listarPorMaterial, listar };