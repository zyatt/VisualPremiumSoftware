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

  const precosUnidadeMedida = m.fornecedorMateriais
    .map((fm) => Number(fm.precoUnidadeMedida))
    .filter((p) => p > 0)
    .sort((a, b) => a - b);

  const media = (arr) => {
    if (!arr.length) return null;
    return arr.reduce((a, b) => a + b, 0) / arr.length;
  };

  return {
    ...m,
    precoMediano:              media(precos),
    precoM2Mediano:            media(precosM2),
    precoUnidadeMedidaMediano: media(precosUnidadeMedida),
    custoUltimaCompra:         _normalizarPreco(m.ultimoValorPago),
    custoM2UltimaCompra:       _normalizarPreco(m.ultimoValorPagoM2),
  };
}

// Nome de exibição de um material vinculado a um genérico: "NOME DESCRICAO".
// Para materiais normais (sem descricao), retorna o próprio nome.
function _nomeExibicao(m) {
  if (m.descricao && m.descricao.trim()) {
    return `${m.nome} ${m.descricao.trim()}`;
  }
  return m.nome;
}

const _includeFornecedores = {
  fornecedorMateriais: {
    where: { ativo: true },
    include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
  },
};

// Monta um filtro Prisma para campos numéricos (largura/comprimento) que se
// comporta como uma busca "contém": digitar "1" deve casar com 1, 1.20,
// 1.5, 1.99 etc. (qualquer valor cuja parte inteira seja 1), e digitar
// "1.2" deve casar com 1.2, 1.20, 1.25 etc. (prefixo decimal). Não dá para
// usar `contains` do Prisma em colunas numéricas, então convertemos o texto
// digitado num intervalo [gte, lt) equivalente.
function filtroNumericoContem(valorDigitado) {
  if (valorDigitado === undefined || valorDigitado === null) return null;
  const texto = valorDigitado.toString().trim().replace(',', '.');
  if (texto === '') return null;
  const numero = Number(texto);
  if (Number.isNaN(numero)) return null;

  const casasDecimais = texto.includes('.') ? texto.split('.')[1].length : 0;
  const passo = Math.pow(10, -casasDecimais);
  // Evita problemas de ponto flutuante (ex.: 1.1 + 0.1 = 1.2000000000000002)
  const casasArred = casasDecimais + 2;
  const min = numero;
  const max = Number((numero + passo).toFixed(casasArred));

  return { gte: min, lt: max };
}

async function _montarWhere(filtros = {}) {
  const { busca, categoria, semCategoria, status, comFornecedor, id, medida, espessura, largura, comprimento, identificador, ativo, ehGenerico, materialGenericoId, incluirVinculados } = filtros;

  const where = {};

  // Materiais aguardando aprovação de um ADMIN ficam ocultos das listagens
  // normais de estoque — só aparecem na fila dedicada (listarPendentes).
  where.aguardandoAprovacao = false;

  // Materiais "filhos" de um genérico ficam sempre ocultos das listagens
  // normais de Estoque (aparecem só dentro do dialog do próprio genérico,
  // via listarVinculados). Isso evita duplicar visualmente o mesmo grupo
  // de material na tela de estoque.
  // Passar materialGenericoId explicitamente (ex.: no dialog de vínculo)
  // sobrepõe esse comportamento e busca só os filhos daquele genérico.
  //
  // EXCEÇÃO OPT-IN: telas que precisam localizar uma variante já criada
  // pelo nome (ex.: Orçamento, ao digitar "TINTA AZUL" ou "AZUL") devem
  // passar `incluirVinculados: true` explicitamente junto de `busca` — do
  // contrário nunca reencontrariam a variante, só o genérico "TINTA", e
  // salvar de novo criaria um novo vínculo em vez de reaproveitar o filho.
  // Isso é uma decisão explícita do chamador, não implícita a qualquer
  // busca — a tela de Estoque NUNCA deve passar essa flag.
  if (materialGenericoId !== undefined && materialGenericoId !== '' && materialGenericoId !== null) {
    where.materialGenericoId = Number(materialGenericoId);
  } else if (!(busca && incluirVinculados === 'true')) {
    where.materialGenericoId = null;
  }

  if (ehGenerico === 'true')  where.ehGenerico = true;
  if (ehGenerico === 'false') where.ehGenerico = false;

  if (ativo === 'true') where.ativo = true;
  if (id) where.id = Number(id);
  if (busca) {
    const tokens = busca.trim().split(/\s+/).filter(Boolean);
    // Casa pelo próprio nome OU pelo nome do genérico-pai (para achar
    // filhos digitando o nome do pai) OU pela descrição (para achar
    // "TINTA AZUL" digitando "AZUL").
    const tokenFiltro = (t) => ({
      OR: [
        { nome: { contains: t, mode: 'insensitive' } },
        { descricao: { contains: t, mode: 'insensitive' } },
        { materialGenerico: { nome: { contains: t, mode: 'insensitive' } } },
      ],
    });
    const buscaWhere = tokens.length === 1
      ? tokenFiltro(tokens[0])
      : { AND: tokens.map(tokenFiltro) };

    // As variantes (filhas) ficam sempre ocultas das listagens normais
    // (materialGenericoId = null acima). Isso significa que buscaWhere,
    // sozinho, NUNCA vai casar pela `descricao` de uma variante, já que
    // esse campo só existe nos filhos. Para que digitar a descrição de
    // uma variante (ex.: "AZUL FRISIA FLEET COLOR") continue encontrando
    // e exibindo o material GENÉRICO pai — em Estoque, Controle e
    // Relatório, Ordem de Compra, Solicitação e Produção — procuramos
    // também entre os filhos e trazemos o(s) pai(s) correspondente(s).
    // Isso é pulado quando `incluirVinculados: true`, pois nesse caso o
    // chamador já pediu para localizar a própria variante (ver acima).
    if (incluirVinculados !== 'true') {
      const filtroVariante = tokens.length === 1
        ? tokenFiltro(tokens[0])
        : { AND: tokens.map(tokenFiltro) };

      const filhosCorrespondentes = await prisma.material.findMany({
        where: { materialGenericoId: { not: null }, ...filtroVariante },
        select: { materialGenericoId: true },
        distinct: ['materialGenericoId'],
      });
      const idsGenericosPorVariante = filhosCorrespondentes
        .map((f) => f.materialGenericoId)
        .filter((v) => v !== null);

      if (idsGenericosPorVariante.length > 0) {
        where.OR = [buscaWhere, { id: { in: idsGenericosPorVariante } }];
      } else {
        Object.assign(where, buscaWhere);
      }
    } else {
      Object.assign(where, buscaWhere);
    }
  }
  if (identificador) where.identificador = { contains: identificador, mode: 'insensitive' };
  if (medida)        where.medida        = { contains: medida,        mode: 'insensitive' };
  if (espessura) {
    const espessuraNum = espessura.replace(',', '.').match(/[\d.]+/)?.[0];
    where.espessura = { contains: espessuraNum ?? espessura, mode: 'insensitive' };
  }
  if (largura !== undefined && largura !== '') {
    const filtro = filtroNumericoContem(largura);
    if (filtro) where.largura = filtro;
  }
  if (comprimento !== undefined && comprimento !== '') {
    const filtro = filtroNumericoContem(comprimento);
    if (filtro) where.comprimento = filtro;
  }
  if (semCategoria === 'true') {
    where.categoria = null;
  } else if (categoria) {
    where.categoria = { equals: categoria, mode: 'insensitive' };
  }
  const _statusValidos = new Set(['OK', 'LIMITE', 'CRITICO', 'INATIVO']);
  if (status && _statusValidos.has(status)) where.status = status;
  if (comFornecedor === 'true') {
    where.fornecedorMateriais = { some: { ativo: true } };
  } else if (comFornecedor === 'false') {
    where.fornecedorMateriais = { none: { ativo: true } };
  }

  return where;
}

const _colunasOrdenaveis = new Set([
  'id', 'identificador', 'nome', 'categoria', 'medida', 'espessura',
  'largura', 'comprimento', 'quantidade', 'estoqueMinimo', 'unidade',
  'ultimoValorPago', 'ultimoValorPagoM2', 'status',
]);

function _resolverOrderBy(ordenarPor, direcao) {
  const dir = direcao === 'desc' ? 'desc' : 'asc';
  if (ordenarPor && _colunasOrdenaveis.has(ordenarPor)) {
    return [{ [ordenarPor]: dir }, { id: 'asc' }];
  }
  return [{ ativo: 'desc' }, { nome: 'asc' }];
}

async function listar(filtros = {}) {
  const { limite, pagina, porPagina } = filtros;
  const where = await _montarWhere(filtros);

  const take = limite != null && limite !== ''
    ? Number(limite)
    : (porPagina != null && porPagina !== '' ? Number(porPagina) : undefined);
  const skip = (pagina != null && pagina !== '' && porPagina != null && porPagina !== '')
    ? (Number(pagina) - 1) * Number(porPagina)
    : undefined;

  const materiais = await prisma.material.findMany({
    where,
    include: _includeFornecedores,
    orderBy: [{ ativo: 'desc' }, { nome: 'asc' }],
    ...(take !== undefined ? { take } : {}),
    ...(skip !== undefined ? { skip } : {}),
  });

  return materiais.map(_mapearMaterial);
}

async function _listarPaginadoPorMedia(where, { campoMedia, direcao, take, skip, total }) {
  const filtrados = await prisma.material.findMany({ where, select: { id: true } });
  const ids = filtrados.map((m) => m.id);

  if (ids.length === 0) return { data: [], total };

  const colunaPreco = campoMedia === 'precoM2Mediano' ? 'precoMetroQuadrado' : 'preco';
  const dir = direcao === 'desc' ? 'DESC' : 'ASC';

  const idsPagina = await prisma.$queryRawUnsafe(
    `
      SELECT m.id
      FROM materiais m
      LEFT JOIN fornecedor_materiais fm
        ON fm."materialId" = m.id AND fm.ativo = true AND fm."${colunaPreco}" > 0
      WHERE m.id = ANY($1::int[])
      GROUP BY m.id
      ORDER BY AVG(fm."${colunaPreco}") ${dir} NULLS LAST, m.id ASC
      LIMIT $2 OFFSET $3
    `,
    ids,
    take,
    skip,
  );

  const idsOrdenados = idsPagina.map((r) => r.id);
  if (idsOrdenados.length === 0) return { data: [], total };

  const materiais = await prisma.material.findMany({
    where: { id: { in: idsOrdenados } },
    include: _includeFornecedores,
  });
  const porId = new Map(materiais.map((m) => [m.id, m]));
  const emOrdem = idsOrdenados.map((id) => porId.get(id)).filter(Boolean);

  return { data: emOrdem.map(_mapearMaterial), total };
}

async function listarPaginado(filtros = {}) {
  const { pagina = 1, porPagina = 50, ordenarPor, direcao } = filtros;
  const where = await _montarWhere(filtros);

  const take = Number(porPagina) || 50;
  const skip = (Number(pagina) - 1) * take;

  const total = await prisma.material.count({ where });

  if (ordenarPor === 'precoMediano' || ordenarPor === 'precoM2Mediano') {
    return _listarPaginadoPorMedia(where, { campoMedia: ordenarPor, direcao, take, skip, total });
  }

  const materiais = await prisma.material.findMany({
    where,
    include: _includeFornecedores,
    orderBy: _resolverOrderBy(ordenarPor, direcao),
    take,
    skip,
  });

  return { data: materiais.map(_mapearMaterial), total };
}

async function listarParaMovimentacao(filtros = {}) {
  const { pagina = 1, porPagina = 50 } = filtros;
  return listarPaginado({
    ...filtros,
    ativo:      'true',
    pagina,
    porPagina,
    ordenarPor: filtros.ordenarPor ?? 'nome',
    direcao:    filtros.direcao,
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
    },
  });

  if (!m) return null;

  return _mapearMaterial(m);
}

async function _validarVinculoGenerico(data, { idAtual } = {}) {
  const ehGenerico = !!data.ehGenerico;
  const materialGenericoId = data.materialGenericoId != null && data.materialGenericoId !== ''
    ? Number(data.materialGenericoId)
    : null;
  const descricao = data.descricao?.trim() || null;

  if (ehGenerico && materialGenericoId) {
    throw { status: 400, message: 'Um material genérico não pode estar vinculado a outro material genérico.' };
  }

  if (materialGenericoId) {
    if (idAtual && materialGenericoId === idAtual) {
      throw { status: 400, message: 'Um material não pode ser vinculado a si mesmo.' };
    }
    if (!descricao) {
      throw { status: 400, message: 'Informe uma descrição para vincular este material ao material genérico.' };
    }
    const pai = await prisma.material.findUnique({ where: { id: materialGenericoId } });
    if (!pai) throw { status: 404, message: 'Material genérico não encontrado.' };
    if (!pai.ehGenerico) {
      throw { status: 400, message: 'O material selecionado não é um material genérico.' };
    }
  } else if (data.materialGenericoId !== undefined) {
    // materialGenericoId explicitamente removido: também não faz sentido manter descrição.
  }

  return { ehGenerico, materialGenericoId, descricao };
}

async function criar(data, usuarioId, usuarioNome, usuarioRole) {
  const { ehGenerico, materialGenericoId, descricao } = await _validarVinculoGenerico(data);
  data.ehGenerico         = ehGenerico;
  data.materialGenericoId = materialGenericoId;
  data.descricao          = materialGenericoId ? descricao : null;

  const nomeTrimmed      = data.nome?.trim();
  const medidaTrimmed    = data.medida?.trim()       ?? null;
  const espessuraTrimmed = data.espessura?.trim()    ?? null;

  const identificadorTrimmed = data.identificador?.trim() ?? null;

  // Materiais vinculados a um genérico se diferenciam pela descrição, não
  // pela combinação nome/identificador/medida/espessura — então a checagem
  // de duplicado padrão (que ignora descricao) não se aplica a eles.
  const duplicado = materialGenericoId
    ? null
    : await prisma.material.findFirst({
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

  // Usuários que não são ADMIN têm o cadastro colocado em fila de
  // aprovação: o material é criado normalmente no banco, mas fica marcado
  // com aguardandoAprovacao = true e some das listagens padrão de estoque
  // até um ADMIN revisar, editar se necessário e aprovar.
  const precisaAprovacao = usuarioRole && usuarioRole !== 'ADMIN';

  const status = calcularStatus(data.quantidade || 0, data.estoqueMinimo || 0, true);
  data.ultimoValorPago   = _normalizarPreco(data.ultimoValorPago);
  data.ultimoValorPagoM2 = _normalizarPreco(data.ultimoValorPagoM2);

  try {
    const material = await prisma.material.create({
      data: {
        ...data,
        status,
        aguardandoAprovacao: !!precisaAprovacao,
        criadoPorId:   usuarioId ?? null,
        criadoPorNome: usuarioNome ?? null,
      },
    });

    await auditSvc.registrar(material.id, precisaAprovacao ? 'CADASTRO_PENDENTE' : 'CADASTRO', {
      valorDepois: material.nome,
      usuarioId,
      usuarioNome,
      material,
    });

    if (!precisaAprovacao) {
      _broadcast('material_atualizado', {
        motivo: 'criar',
        materialId: material.id,
        nome: material.nome,
      }, usuarioId);
    } else {
      _broadcast('material_pendente_aprovacao', {
        materialId: material.id,
        nome: material.nome,
      }, usuarioId);
    }

    return material;
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

async function atualizar(id, data, usuarioId, usuarioNome) {
  const atual = await prisma.material.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Material não encontrado' };

  if (atual.ehGenerico) {
    const temFilhos = await prisma.material.count({ where: { materialGenericoId: id } });
    if (temFilhos > 0 && data.ehGenerico === false) {
      throw { status: 400, message: 'Não é possível desmarcar como genérico: existem materiais vinculados a ele.' };
    }
  }

  const dadosParaValidar = {
    ehGenerico:         data.ehGenerico ?? atual.ehGenerico,
    materialGenericoId: data.materialGenericoId !== undefined ? data.materialGenericoId : atual.materialGenericoId,
    descricao:          data.descricao !== undefined ? data.descricao : atual.descricao,
  };
  const { ehGenerico, materialGenericoId, descricao } = await _validarVinculoGenerico(dadosParaValidar, { idAtual: id });
  data.ehGenerico         = ehGenerico;
  data.materialGenericoId = materialGenericoId;
  data.descricao          = materialGenericoId ? descricao : null;

  const nomeTrimmed        = (data.nome        ?? atual.nome)?.trim();
  const medidaTrimmed      = (data.medida       ?? atual.medida)?.trim()       ?? null;
  const espessuraTrimmed   = (data.espessura    ?? atual.espessura)?.trim()    ?? null;

  const identificadorTrimmed = (data.identificador ?? atual.identificador)?.trim() ?? null;
  const duplicado = materialGenericoId
    ? null
    : await prisma.material.findFirst({
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

async function listarPendentes() {
  const materiais = await prisma.material.findMany({
    where: { aguardandoAprovacao: true },
    include: _includeFornecedores,
    orderBy: { criadoEm: 'asc' },
  });
  return materiais.map(_mapearMaterial);
}

async function contarPendentes() {
  return prisma.material.count({ where: { aguardandoAprovacao: true } });
}

/// Aprova um material que estava aguardando aprovação. O ADMIN pode enviar
/// `data` com qualquer campo alterado (mesmo conjunto aceito por
/// `atualizar`) — esses valores são aplicados antes de tirar o material da
/// fila. Se `data` vier vazio/undefined, o material é aprovado como foi
/// originalmente cadastrado.
async function aprovar(id, data = {}, usuarioId, usuarioNome) {
  const atual = await prisma.material.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Material não encontrado' };
  if (!atual.aguardandoAprovacao) {
    throw { status: 400, message: 'Este material não está aguardando aprovação' };
  }

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
  const status = calcularStatus(quantidade, estoqueMinimo, true);

  if (data.ultimoValorPago !== undefined) {
    data.ultimoValorPago = _normalizarPreco(data.ultimoValorPago);
  }
  if (data.ultimoValorPagoM2 !== undefined) {
    data.ultimoValorPagoM2 = _normalizarPreco(data.ultimoValorPagoM2);
  }

  try {
    const material = await prisma.material.update({
      where: { id },
      data: {
        ...data,
        status,
        ativo: true,
        aguardandoAprovacao: false,
        aprovadoPorId:   usuarioId ?? null,
        aprovadoPorNome: usuarioNome ?? null,
        aprovadoEm:      new Date(),
      },
    });

    await auditSvc.registrarEdicao(id, atual, material, usuarioId, usuarioNome);
    await auditSvc.registrar(id, 'APROVACAO_CADASTRO', {
      valorDepois: material.nome,
      usuarioId,
      usuarioNome,
      material,
    });

    _broadcast('material_atualizado', {
      motivo: 'aprovar',
      materialId: material.id,
      nome: material.nome,
    }, usuarioId);

    notificarSeCritico(atual.status, material);

    return material;
  } catch (e) {
    if (e?.code === 'P2002') _throwDuplicado(medidaTrimmed, espessuraTrimmed);
    throw e;
  }
}

/// Recusa (exclui) um cadastro pendente de aprovação. Só permitido enquanto
/// o material ainda estiver aguardando aprovação — depois de aprovado, a
/// exclusão segue o fluxo normal (excluir(), que exige desativação prévia).
async function recusar(id, usuarioId, usuarioNome) {
  const atual = await prisma.material.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Material não encontrado' };
  if (!atual.aguardandoAprovacao) {
    throw { status: 400, message: 'Este material não está aguardando aprovação' };
  }

  let deletado;
  try {
    deletado = await prisma.material.delete({ where: { id } });
  } catch (e) {
    if (e?.code === 'P2003') {
      throw {
        status: 400,
        message: 'Não é possível recusar: já existem registros vinculados a este material.',
      };
    }
    throw e;
  }

  await auditSvc.registrar(id, 'RECUSA_CADASTRO', {
    valorAntes: atual.nome,
    usuarioId,
    usuarioNome,
    material: atual,
  });

  _broadcast('material_atualizado', { motivo: 'recusar', materialId: id }, usuarioId);
  return deletado;
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

  await prisma.ordemCompraItem.updateMany({
    where: { materialId: id },
    data: {
      materialId:    null,
      descricaoItem: material.nome,
    },
  });

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

/// Lista todos os materiais vinculados (filhos) de um material genérico.
/// Usado pelo dialog que abre ao selecionar um material genérico em
/// Orçamento/Ordem de Compra/Solicitações/Estoque.
async function listarVinculados(materialGenericoId, { apenasAtivos } = {}) {
  const generico = await prisma.material.findUnique({
    where: { id: materialGenericoId },
    include: _includeFornecedores,
  });
  if (!generico) throw { status: 404, message: 'Material não encontrado' };
  if (!generico.ehGenerico) {
    throw { status: 400, message: 'Este material não é um material genérico' };
  }

  const where = { materialGenericoId };
  if (apenasAtivos) where.ativo = true;

  const vinculados = await prisma.material.findMany({
    where,
    include: _includeFornecedores,
    orderBy: [{ ativo: 'desc' }, { descricao: 'asc' }],
  });

  return {
    generico: _mapearMaterial(generico),
    itens: vinculados.map((m) => ({ ..._mapearMaterial(m), nomeExibicao: _nomeExibicao(m) })),
  };
}

/// Resolve (ou cria) o Material "filho" de um genérico para uma descrição
/// específica. Idempotente: se um filho com essa descrição já existir
/// (comparação case-insensitive, ignorando espaços nas pontas), retorna
/// ele; caso contrário cria um novo, copiando dados default do genérico
/// (unidade, categoria) para o filho começar consistente.
///
/// Usado pelo orçamento (adicionarItem/atualizarItem/substituirItens) para
/// que cada variante de um material genérico (ex.: "TINTA" + "AZUL",
/// "TINTA" + "cc") vire um Material concreto com id próprio — o que
/// automaticamente resolve o vínculo fornecedor-material (FornecedorMaterial
/// é único por materialId) e o estoque, preço e histórico de cada variante
/// sem qualquer alteração nessas outras tabelas.
///
/// Usa SELECT ... FOR UPDATE dentro de uma transação para evitar que duas
/// requisições concorrentes criem dois filhos duplicados com a mesma
/// descrição (mesma técnica de lock já usada em orcamento.service.js).
async function resolverOuCriarFilho(materialGenericoId, descricao) {
  const descTrimmed = descricao?.trim();
  if (!descTrimmed) {
    throw { status: 400, message: 'Informe uma descrição para este material genérico.' };
  }

  return prisma.$transaction(async (tx) => {
    const genericoRows = await tx.$queryRaw`
      SELECT * FROM materiais WHERE id = ${materialGenericoId} FOR UPDATE
    `;
    const generico = genericoRows[0];
    if (!generico) throw { status: 404, message: 'Material genérico não encontrado.' };
    if (!generico.ehGenerico) {
      throw { status: 400, message: 'O material selecionado não é um material genérico.' };
    }

    const filhoExistente = await tx.material.findFirst({
      where: {
        materialGenericoId,
        descricao: { equals: descTrimmed, mode: 'insensitive' },
      },
    });
    if (filhoExistente) return filhoExistente;

    try {
      return await tx.material.create({
        data: {
          nome: generico.nome,
          unidade: generico.unidade,
          categoria: generico.categoria,
          materialGenericoId,
          descricao: descTrimmed,
          ehGenerico: false,
          // quantidade/estoqueMinimo começam em 0/0, então calcularStatus
          // resolve para 'LIMITE' (q === min) — evita cair no default
          // 'OK' do schema, que ficaria inconsistente com o resto do
          // sistema (reativar, criar, atualizar sempre passam por
          // calcularStatus).
          status: calcularStatus(0, 0, true),
        },
      });
    } catch (e) {
      // Corrida rara: outra transação criou o mesmo filho entre o
      // findFirst acima e este create (ex.: dois requests bem próximos
      // sem lock efetivo por algum motivo). O índice único de expressão
      // (materiais_generico_descricao_null_safe_key) barra o duplicado —
      // nesse caso, apenas busca e retorna o que já foi criado.
      if (e?.code === 'P2002') {
        const jaCriado = await tx.material.findFirst({
          where: {
            materialGenericoId,
            descricao: { equals: descTrimmed, mode: 'insensitive' },
          },
        });
        if (jaCriado) return jaCriado;
      }
      throw e;
    }
  });
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

  // Registra o lançamento manual no histórico de compras, para que ele
  // apareça no modal (card "Preço / Preço m²" e tabela) igual a um preço
  // vindo de Ordem de Compra. Sem OC e sem fornecedor => manual = true.
  await prisma.historicoPrecoMaterial.create({
    data: {
      materialId:    id,
      manual:        true,
      quantidade:    0,
      precoUnitario: novoUnitario ?? null,
      precoM2:       novoM2 ?? null,
      usarM2:        novoUnitario === undefined && novoM2 !== undefined,
    },
  });

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

  const resultCompleto = await prisma.material.findUnique({
    where: { id },
    include: _includeFornecedores,
  });

  return _mapearMaterial(resultCompleto);
}

module.exports = {
  calcularStatus,
  notificarSeCritico,
  filtroNumericoContem,
  listar,
  listarPaginado,
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
  listarPendentes,
  contarPendentes,
  aprovar,
  recusar,
  listarVinculados,
  resolverOuCriarFilho,
};