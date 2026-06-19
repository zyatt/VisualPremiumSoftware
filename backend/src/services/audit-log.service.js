// audit-log.service.js
// Responsável por gravar e consultar o histórico de alterações de materiais.
// Deve ser chamado nos pontos certos do material.service.js (ver comentários abaixo).

const prisma = require('../utils/prisma');

// ── Campos "amigáveis" para exibição ─────────────────────────────────────────
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

// Campos que NÃO devem gerar entrada no audit log (metadados internos)
const _IGNORAR = new Set([
  'criadoEm', 'atualizadoEm', 'id',
]);

// ── Helpers ───────────────────────────────────────────────────────────────────

function _str(v) {
  if (v === null || v === undefined) return null;
  // Objetos aninhados não devem ser serializados como JSON bruto —
  // retorna null para que o chamador trate campo a campo.
  if (typeof v === 'object' && !Array.isArray(v)) return null;
  return String(v);
}

function _label(campo) {
  return _LABELS[campo] ?? campo;
}

// ── Registrar (interno — chamado pelos outros services) ───────────────────────

/**
 * Cria um ou mais registros de audit_log_materiais.
 *
 * @param {number}  materialId
 * @param {string}  acao        - 'CADASTRO' | 'EDICAO' | 'DESATIVACAO' | 'REATIVACAO' | 'EXCLUSAO' | 'ESTOQUE_CONFIRMADO'
 * @param {object}  opts
 * @param {string}  [opts.campo]       - campo alterado (EDICAO)
 * @param {*}       [opts.valorAntes]  - valor anterior
 * @param {*}       [opts.valorDepois] - novo valor
 * @param {number}  [opts.usuarioId]
 * @param {string}  [opts.usuarioNome]
 */
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

/**
 * Compara dois snapshots de material e registra um log por campo alterado.
 * Ignora campos de metadados e campos cujos valores são idênticos.
 */
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

// ── Consultar ─────────────────────────────────────────────────────────────────

/**
 * Lista logs de um material específico (mais recentes primeiro).
 */
async function listarPorMaterial(materialId, limite = 200) {
  return prisma.auditLogMaterial.findMany({
    where:   { materialId: Number(materialId) },
    orderBy: { criadoEm: 'desc' },
    take:    limite,
    include: { material: { select: { id: true, nome: true, categoria: true } } },
  });
}

/**
 * Lista logs globais com filtros opcionais.
 * Parâmetros: materialId, acao, usuarioId, dataInicio, dataFim, busca (nome do material), limite.
 */
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