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

// Monta o snapshot dos dados descritivos do material a partir do próprio
// objeto `material` (antes ou depois da operação). Esse snapshot é gravado
// junto do log para que o histórico continue exibindo nome/unidade/medida/
// etc. mesmo depois que o material for excluído do banco (hard delete) —
// nesse caso o JOIN com a tabela material passa a retornar null, então o
// log não pode depender apenas do relacionamento.
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

  // Quando o material já foi excluído (ex.: log de EXCLUSAO gravado após o
  // delete), a FK materialId aponta para uma linha que não existe mais.
  // Com onDelete: SetNull no schema, o banco aceita NULL nesse campo, então
  // passamos null explicitamente — o snapshot (*Snap) preserva os dados.
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
  // Snapshot tirado do estado "depois" (dados atuais do material no momento
  // da edição), usado igualmente em todas as entradas geradas por esta edição.
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

// Seleção completa dos campos do material usados na exibição do histórico
// (nome, unidade, medida, espessura, identificador, largura, comprimento).
const _MATERIAL_SELECT = {
  id: true, nome: true, categoria: true, unidade: true,
  medida: true, espessura: true, identificador: true,
  largura: true, comprimento: true,
};

// Achata o snapshot gravado no log (colunas *Snap) num objeto `material`
// no mesmo formato do include do Prisma, para os consumidores (controller/
// frontend) não precisarem tratar dois formatos diferentes. Se o material
// ainda existe (JOIN não-nulo), os dados atuais têm prioridade; senão,
// cai no snapshot gravado no momento da ação — é o que garante que
// exclusões continuem aparecendo no histórico com os dados corretos.
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
    // Busca tanto pelo nome atual do material (JOIN) quanto pelo nome
    // salvo no snapshot — necessário porque materiais excluídos não têm
    // mais linha na tabela material, então o JOIN sozinho não os encontraria.
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