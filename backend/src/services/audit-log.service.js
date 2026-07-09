const prisma = require('../utils/prisma');

const _LABELS = {
  nome:              'Nome',
  unidade:           'Unidade',
  categoria:         'Categoria',
  medida:            'Medida',
  espessura:         'Espessura',
  identificador:     'Identificador',
  valor:             'Valor',
  valorMetroQuadrado:'Valor m²',
  quantidade:        'Quantidade',
  estoqueMinimo:     'Estoque Mínimo',
  status:            'Status',
  ativo:             'Ativo',
  ultimoValorPago:   'Último Valor Pago',
  ultimoValorPagoM2: 'Último Valor Pago m²',
};

const _IGNORAR = new Set([
  'criadoEm', 'atualizadoEm', 'id',
]);

function _str(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'object' && !Array.isArray(v)) return null;
  return String(v);
}

function _label(campo) {
  return _LABELS[campo] ?? campo;
}

async function registrar(materialId, acao, opts = {}) {
  const { campo, valorAntes, valorDepois, usuarioId, usuarioNome } = opts;
  await prisma.auditLogMaterial.create({
    data: {
      materialId,
      acao,
      campo:       campo      ?? null,
      valorAntes:  _str(valorAntes),
      valorDepois: _str(valorDepois),
      usuarioId:   usuarioId  ?? null,
      usuarioNome: usuarioNome ?? null,
    },
  });
}

async function registrarEdicao(materialId, antes, depois, usuarioId, usuarioNome) {
  const campos = new Set([...Object.keys(antes), ...Object.keys(depois)]);
  const promessas = [];

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
        },
      })
    );
  }

  if (promessas.length > 0) await Promise.all(promessas);
}

async function listarPorMaterial(materialId, limite = 200) {
  return prisma.auditLogMaterial.findMany({
    where:   { materialId: Number(materialId) },
    orderBy: { criadoEm: 'desc' },
    take:    limite,
    include: { material: { select: { id: true, nome: true, categoria: true } } },
  });
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
    where.material = { nome: { contains: busca, mode: 'insensitive' } };
  }

  return prisma.auditLogMaterial.findMany({
    where,
    orderBy: { criadoEm: 'desc' },
    take:    Number(limite),
    include: {
      material: {
        select: { id: true, nome: true, categoria: true, medida: true, espessura: true },
      },
    },
  });
}

module.exports = { registrar, registrarEdicao, listarPorMaterial, listar };