const prisma = require('../utils/prisma');
const materialSvc = require('./material.service');
const fornecedorSvc = require('./fornecedor.service');

function _normalizarPreco(valor) {
  if (valor == null) return null;
  const num = Number(valor);
  return num > 0 ? num : null;
}

function _normalizarNumerosOS(numerosOS) {
  if (!numerosOS) return [];
  if (typeof numerosOS === 'string') return numerosOS.trim() ? [numerosOS.trim()] : [];
  if (!Array.isArray(numerosOS)) return [];
  return numerosOS
    .map((n) => (typeof n === 'object' && n !== null ? n.numeroOS : n))
    .map((n) => String(n).trim())
    .filter(Boolean);
}

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _calcularQuantidadeReal({ quantidade, usarM2, qtdUnidade }) {
    if (usarM2) return Number(quantidade);

    const qtdUnit = Number(qtdUnidade ?? 0);
    if (qtdUnit > 0) {
        return Number(quantidade) * qtdUnit;
    }

    return Number(quantidade);
}

function _expandirItensComDistribuicao(itens) {
  const resultado = [];
  for (const item of itens) {
    const dist = Array.isArray(item.distribuicao)
      ? item.distribuicao.filter((l) => l.os && String(l.os).trim() && Number(l.quantidade) > 0)
      : [];

    if (dist.length > 0) {
      // O precoTotal do item (rascunho da tela) é a fonte da verdade —
      // ver comentário em criar()/atualizar(). Ao expandir por OS,
      // rateamos esse total proporcionalmente à quantidade de cada
      // linha, em vez de recalcular cada linha do zero a partir de
      // precoUnitario (que amplificaria o arredondamento de exibição).
      // A última linha recebe o resto da divisão para garantir que a
      // soma das linhas expandidas seja EXATAMENTE igual ao total
      // original, sem sobra nem falta por arredondamento de centavos.
      const precoTotalItem = Number(item.precoTotal ?? 0);
      const quantidadeTotalItem = dist.reduce((acc, l) => acc + Number(l.quantidade), 0);
      const usarRateio = precoTotalItem > 0 && quantidadeTotalItem > 0;

      let precoTotalAcumulado = 0;
      dist.forEach((linha, idx) => {
        let precoTotal;
        if (usarRateio) {
          if (idx === dist.length - 1) {
            // última linha: resto exato, sem perda de centavos por
            // arredondamento nas linhas anteriores
            precoTotal = Number((precoTotalItem - precoTotalAcumulado).toFixed(2));
          } else {
            precoTotal = Number(
              ((Number(linha.quantidade) / quantidadeTotalItem) * precoTotalItem).toFixed(2)
            );
          }
          precoTotalAcumulado += precoTotal;
        } else if (item.usarM2 && Number(item.precoMetroQuadrado) > 0) {
          precoTotal = Number(linha.quantidade) * Number(item.precoMetroQuadrado);
        } else {
          const precoUnit = Number(item.precoUnitario ?? 0);
          const qtdUnit = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
          if (qtdUnit != null && qtdUnit > 0) {
            precoTotal = Number(linha.quantidade) * qtdUnit * precoUnit;
          } else {
            precoTotal = Number(linha.quantidade) * precoUnit;
          }
        }

        resultado.push({
          ...item,
          numeroOS:   String(linha.os).trim(),
          quantidade: Number(linha.quantidade),
          precoTotal,
        });
      });
    } else {
      resultado.push(item);
    }
  }
  return resultado;
}

/// Resolve itens que apontam para um material genérico (ehGenerico: true)
/// para o Material filho concreto correspondente à descrição informada,
/// criando o filho se ainda não existir (mesma lógica usada em
/// orcamento.service.js). Sem isso, a OC salvava o item com o materialId
/// do próprio genérico — que fica oculto de todas as listagens de estoque
/// — e ao finalizar a OC o estoque era creditado nesse registro fantasma,
/// nunca aparecendo em lugar nenhum.
///
/// Retorna uma NOVA lista de itens (não modifica o array original), com
/// materialId sempre apontando para um material concreto e descricaoItem
/// zerado para os itens que foram resolvidos (a descrição já passa a
/// viver no Material filho, como em orçamento).
async function _resolverMateriaisGenericos(itens) {
  const cache = new Map(); // `${materialId}::${descricaoLower}` -> filho resolvido

  const resultado = [];
  for (const item of itens) {
    if (!item.materialId) {
      resultado.push(item);
      continue;
    }

    const material = await prisma.material.findUnique({
      where: { id: Number(item.materialId) },
      select: { id: true, nome: true, ehGenerico: true },
    });
    if (!material) throw { status: 404, message: `Material ${item.materialId} não encontrado.` };

    if (!material.ehGenerico) {
      // `materialNomeResolvido` só serve para mensagens de erro (ver
      // _validarSemItensDuplicados) — nunca é persistido no OrdemCompraItem.
      resultado.push({ ...item, materialNomeResolvido: material.nome });
      continue;
    }

    const desc = item.descricaoItem != null && String(item.descricaoItem).trim()
      ? String(item.descricaoItem).trim()
      : null;
    if (!desc) {
      throw {
        status: 400,
        message: 'Este material é genérico: preencha a descrição do item antes de salvar.',
      };
    }

    const chave = `${material.id}::${desc.toLowerCase()}`;
    let filho = cache.get(chave);
    if (!filho) {
      filho = await materialSvc.resolverOuCriarFilho(material.id, desc);
      cache.set(chave, filho);
    }

    // `materialGenericoOrigemId` guarda o id do genérico "pai" que deu
    // origem a este item, mesmo depois de materialId já apontar pro
    // filho concreto. É usado só internamente por
    // _sincronizarVinculosFornecedor[PorTotal] pra também vincular o
    // genérico ao fornecedor (ver comentário lá) — nunca é persistido
    // no OrdemCompraItem. `materialNomeResolvido` (mesma ideia, só para
    // mensagens de erro) segue o mesmo tratamento.
    resultado.push({
      ...item,
      materialId: filho.id,
      descricaoItem: null,
      materialGenericoOrigemId: material.id,
      materialNomeResolvido: filho.descricao ? `${filho.nome} · ${filho.descricao}` : filho.nome,
    });
  }
  return resultado;
}

/// Impede que a mesma variante de material (mesmo materialId já resolvido)
/// apareça duas vezes na lista de itens de uma OC — mesma regra que
/// orcamento.service.js já aplica em substituirItens/salvarRascunho. Sem
/// isso, adicionar "TINTA · ABC" duas vezes (ex.: uma vez pela variante já
/// vinculada, outra informando a descrição "ABC" de novo pro genérico)
/// cria dois OrdemCompraItem apontando pro mesmo Material, duplicando
/// quantidade/estoque na finalização sem nenhum aviso.
///
/// Recebe a lista JÁ resolvida (pós _resolverMateriaisGenericos, portanto
/// antes de _expandirItensComDistribuicao — a expansão por OS é o que
/// legitimamente repete o mesmo materialId em múltiplas linhas).
function _validarSemItensDuplicados(itensResolvidos) {
  const vistos = new Map(); // materialId -> nome de exibição
  for (const item of itensResolvidos) {
    if (!item.materialId) continue;
    const mid = Number(item.materialId);
    if (vistos.has(mid)) {
      const nome = vistos.get(mid) || item.materialNomeResolvido;
      throw {
        status: 400,
        message: nome
          ? `Item duplicado: "${nome}" já foi adicionado a esta ordem de compra.`
          : `Item duplicado para o material ${mid}.`,
      };
    }
    vistos.set(mid, item.materialNomeResolvido);
  }
}

const _selectMaterial = {
  id: true,
  nome: true,
  descricao: true,
  unidade: true,
  medida: true,
  espessura: true,
  identificador: true,
  largura: true,
  comprimento: true,
  ehGenerico: true,
};

async function _vincularGenericosDeOrigem(fornecedorId, itens) {
  // Garante que todo material genérico que originou algum item da OC
  // (via _resolverMateriaisGenericos) também fique vinculado ao
  // fornecedor — mesmo "vínculo de presença" sem preço que
  // fornecedor.service.js já garante quando o usuário vincula uma
  // variante manualmente pela tela de Fornecedores. Sem isso, itens de
  // OC que resolveram um genérico direto (fluxo "Adicionar genérico
  // com descrição" da tela de Ordem de Compra) nunca deixam o pai
  // vinculado, e ele continua aparecendo como "Novo vínculo" pra
  // sempre nas próximas OCs desse fornecedor.
  if (!fornecedorId) return;
  const genericosIds = new Set();
  for (const item of itens) {
    if (item.materialGenericoOrigemId) genericosIds.add(Number(item.materialGenericoOrigemId));
  }
  for (const materialGenericoId of genericosIds) {
    await fornecedorSvc._garantirVinculoGenerico(fornecedorId, materialGenericoId);
  }
}

async function _sincronizarVinculosFornecedor(fornecedorId, itens) {
  if (!fornecedorId || !Array.isArray(itens) || itens.length === 0) return;

  await _vincularGenericosDeOrigem(fornecedorId, itens);

  const porMaterial = new Map();
  for (const item of itens) {
    const mid = Number(item.materialId);
    if (!mid) continue;

    const qtdUnit = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
    const precoUnitBruto = Number(item.precoUnitario ?? 0);
    const usaUnidadeMedida = qtdUnit != null && qtdUnit > 0;
    const precoPorEmbalagem = usaUnidadeMedida
      ? precoUnitBruto * qtdUnit
      : precoUnitBruto;

    const existing = porMaterial.get(mid);
    if (!existing) {
      porMaterial.set(mid, {
        materialId: mid,
        usarM2:     item.usarM2 ?? false,
        preco:      usaUnidadeMedida ? 0 : precoPorEmbalagem,
        precoM2:    Number(item.precoMetroQuadrado ?? 0),
        precoUnidadeMedida: usaUnidadeMedida ? precoUnitBruto : 0,
      });
    } else {
      if (!usaUnidadeMedida && precoPorEmbalagem > existing.preco) existing.preco = precoPorEmbalagem;
      if (Number(item.precoMetroQuadrado ?? 0) > existing.precoM2) existing.precoM2 = Number(item.precoMetroQuadrado);
      if (usaUnidadeMedida && precoUnitBruto > existing.precoUnidadeMedida) existing.precoUnidadeMedida = precoUnitBruto;
    }
  }

  for (const [materialId, dados] of porMaterial) {
    const updateData = {};
    if (!dados.usarM2 && dados.preco > 0) updateData.preco = dados.preco;
    if (dados.usarM2 && dados.precoM2 > 0) updateData.precoMetroQuadrado = dados.precoM2;
    if (!dados.usarM2 && dados.precoM2 > 0) updateData.precoMetroQuadrado = dados.precoM2;
    if (!dados.usarM2 && dados.precoUnidadeMedida > 0) updateData.precoUnidadeMedida = dados.precoUnidadeMedida;

    if (Object.keys(updateData).length === 0) continue;

    await prisma.fornecedorMaterial.upsert({
      where:  { fornecedorId_materialId: { fornecedorId, materialId } },
      create: {
        fornecedorId,
        materialId,
        preco:               updateData.preco               ?? null,
        precoMetroQuadrado:  updateData.precoMetroQuadrado  ?? null,
        precoUnidadeMedida:  updateData.precoUnidadeMedida  ?? null,
        ativo: true,
      },
      update: {
        ...updateData,
        ativo: true,
      },
    });
  }
}

async function _sincronizarVinculosFornecedorPorTotal(fornecedorId, itens) {
  if (!fornecedorId || !Array.isArray(itens) || itens.length === 0) return;

  await _vincularGenericosDeOrigem(fornecedorId, itens);

  const porMaterial = new Map();
  for (const item of itens) {
    if (!item.materialId) continue;
    const mid = Number(item.materialId);

    const totalItem = Number(item.precoTotal ?? 0);
    if (totalItem <= 0) continue;

    const quantidadeEmbalagens = Number(item.quantidade ?? 0);
    if (quantidadeEmbalagens <= 0) continue;

    const quantidadeReal = _calcularQuantidadeReal({
      quantidade: item.quantidade,
      usarM2:     item.usarM2,
      qtdUnidade: item.qtdUnidade,
    });
    if (quantidadeReal <= 0) continue;

    const existing = porMaterial.get(mid) || {
      totalAcumulado: 0,
      quantidadeEmbalagensAcumulada: 0,
      quantidadeRealAcumulada: 0,
      usarM2: item.usarM2 ?? false,
    };
    existing.totalAcumulado += totalItem;
    existing.quantidadeEmbalagensAcumulada += quantidadeEmbalagens;
    existing.quantidadeRealAcumulada += quantidadeReal;
    existing.usarM2 = existing.usarM2 || (item.usarM2 ?? false);
    porMaterial.set(mid, existing);
  }

  for (const [materialId, dados] of porMaterial) {
    if (dados.usarM2) {
      if (dados.quantidadeRealAcumulada <= 0) continue;
      const precoMedioM2 = dados.totalAcumulado / dados.quantidadeRealAcumulada;
      if (!(precoMedioM2 > 0)) continue;

      await prisma.fornecedorMaterial.upsert({
        where:  { fornecedorId_materialId: { fornecedorId, materialId } },
        create: {
          fornecedorId,
          materialId,
          precoMetroQuadrado: precoMedioM2,
          ativo: true,
        },
        update: {
          precoMetroQuadrado: precoMedioM2,
          ativo: true,
        },
      });
      continue;
    }

    const precoPorEmbalagem = dados.quantidadeEmbalagensAcumulada > 0
      ? dados.totalAcumulado / dados.quantidadeEmbalagensAcumulada
      : 0;
    const precoPorMedida = dados.quantidadeRealAcumulada > 0
      ? dados.totalAcumulado / dados.quantidadeRealAcumulada
      : 0;

    const updateData = {};
    if (precoPorEmbalagem > 0) updateData.preco = precoPorEmbalagem;
    if (precoPorMedida > 0) updateData.precoUnidadeMedida = precoPorMedida;

    if (Object.keys(updateData).length === 0) continue;

    await prisma.fornecedorMaterial.upsert({
      where:  { fornecedorId_materialId: { fornecedorId, materialId } },
      create: {
        fornecedorId,
        materialId,
        preco:               precoPorEmbalagem > 0 ? precoPorEmbalagem : null,
        precoUnidadeMedida:  precoPorMedida > 0 ? precoPorMedida : null,
        ativo: true,
      },
      update: {
        ...updateData,
        ativo: true,
      },
    });
  }
}

async function listar(status) {
  const where = {};
  if (status) where.status = status;
  return prisma.ordemCompra.findMany({
    where,
    include: {
      fornecedor: { select: { id: true, nomeFantasia: true } },
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: { material: { select: _selectMaterial } },
      },
      numerosOS: true,
    },
    orderBy: { criadoEm: 'desc' },
  });
}

async function listarPagina(filtros = {}) {
  const {
    status,
    numero,
    material,
    identificador,
    medida,
    comprimento,
    largura,
    espessura,
    pagina = 1,
    porPagina = 50,
  } = filtros;

  const where = {};
  if (status) where.status = status;

  const numeroNum = numero != null && String(numero).trim() !== ''
    ? Number(String(numero).trim())
    : null;
  if (numeroNum != null && !Number.isNaN(numeroNum)) where.id = numeroNum;

  const itemMaterialWhere = {};
  if (material) {
    // Também casa pela `descricao` (variante) e pelo nome do genérico-pai,
    // não só pelo `nome` — para que digitar a descrição de uma variante
    // encontre a Ordem de Compra que tem aquele material.
    const tokens = material.trim().split(/\s+/).filter(Boolean);
    const tokenFiltro = (t) => ({
      OR: [
        { nome: { contains: t, mode: 'insensitive' } },
        { descricao: { contains: t, mode: 'insensitive' } },
        { materialGenerico: { nome: { contains: t, mode: 'insensitive' } } },
      ],
    });
    if (tokens.length === 1) {
      Object.assign(itemMaterialWhere, tokenFiltro(tokens[0]));
    } else {
      itemMaterialWhere.AND = tokens.map(tokenFiltro);
    }
  }
  if (identificador)  itemMaterialWhere.identificador = { contains: identificador, mode: 'insensitive' };
  if (medida)          itemMaterialWhere.medida        = { contains: medida, mode: 'insensitive' };
  if (espessura)        itemMaterialWhere.espessura     = { contains: espessura, mode: 'insensitive' };
  if (comprimento)      itemMaterialWhere.comprimento   = { equals: Number(comprimento) };
  if (largura)           itemMaterialWhere.largura       = { equals: Number(largura) };

  if (Object.keys(itemMaterialWhere).length > 0) {
    where.itens = { some: { material: { is: itemMaterialWhere } } };
  }

  const take = Number(porPagina) || 50;
  const skip = (Number(pagina) - 1) * take;

  const [data, total] = await Promise.all([
    prisma.ordemCompra.findMany({
      where,
      include: {
        fornecedor: { select: { id: true, nomeFantasia: true } },
        usuario:    { select: { id: true, nome: true } },
        itens: {
          include: { material: { select: _selectMaterial } },
        },
        numerosOS: true,
      },
      orderBy: { criadoEm: 'desc' },
      take,
      skip,
    }),
    prisma.ordemCompra.count({ where }),
  ]);

  return { data, total };
}

async function contarPorStatus() {
  const grupos = await prisma.ordemCompra.groupBy({
    by: ['status'],
    _count: { _all: true },
  });
  const resultado = { EM_ANDAMENTO: 0, FINALIZADO: 0, CANCELADO: 0 };
  for (const g of grupos) {
    resultado[g.status] = g._count._all;
  }
  return resultado;
}

async function buscarPorId(id) {
  return prisma.ordemCompra.findUnique({
    where: { id },
    include: {
      fornecedor: true,
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: {
          material: {
            include: {
              fornecedorMateriais: {
                where: { ativo: true },
                include: { fornecedor: { select: { id: true, nomeFantasia: true } } },
              },
            },
          },
        },
      },
      numerosOS: true,
      orcamento: { select: { id: true, titulo: true } },
    },
  });
}

async function criar(data, usuarioId) {
  const { itens, numerosOS, ...ordemData } = data;

  if (ordemData.data !== undefined && ordemData.data !== null) {
    ordemData.data = new Date(ordemData.data);
  }

  if (!ordemData.fornecedorId) {
    throw { status: 400, message: 'Campo obrigatório ausente: fornecedorId' };
  }

  ordemData.requisitante   = ordemData.requisitante?.trim() || 'Não informado';
  ordemData.formaPagamento = ordemData.formaPagamento ?? null;
  ordemData.prazoPagamento = ordemData.prazoPagamento ?? null;
  ordemData.observacoes    = ordemData.observacoes    ?? null;
  ordemData.empresa        = ordemData.empresa        ?? null;
  ordemData.status         = ordemData.status         ?? 'EM_ANDAMENTO';

  const osArray = _normalizarNumerosOS(numerosOS);
  const itensResolvidos = await _resolverMateriaisGenericos(itens || []);
  _validarSemItensDuplicados(itensResolvidos);
  const itensExpandidos = _expandirItensComDistribuicao(itensResolvidos);

  // O valorTotal da OC precisa ser a soma exata do precoTotal que será
  // efetivamente gravado em cada OrdemCompraItem (ver bloco de criação
  // dos itens logo abaixo) — e não um recálculo independente a partir de
  // quantidade × precoUnitario. O precoUnitario exibido/salvo é
  // arredondado para 2 casas na tela, então recalcular o total a partir
  // dele produzia um valorTotal levemente diferente da soma real dos
  // itens (ex.: R$165,00 em vez de R$165,40), mesmo com os itens
  // individuais corretos. Usamos aqui a MESMA regra de "fonte da
  // verdade" (precoTotal enviado pelo front) que o bloco de criação dos
  // itens já aplica, para os dois nunca divergirem.
  const valorTotal = itensExpandidos.reduce((acc, item) => {
    const usarM2 = item.usarM2 ?? false;
    const precoTotalEnviado = Number(item.precoTotal ?? 0);
    let precoItem;
    if (precoTotalEnviado > 0) {
      precoItem = precoTotalEnviado;
    } else if (usarM2 && Number(item.precoMetroQuadrado) > 0) {
      precoItem = Number(item.quantidade) * Number(item.precoMetroQuadrado);
    } else {
      const precoUnit = Number(item.precoUnitario ?? 0);
      const qtdUnit = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
      if (qtdUnit != null && qtdUnit > 0) {
        precoItem = Number(item.quantidade) * qtdUnit * precoUnit;
      } else {
        precoItem = Number(item.quantidade) * precoUnit;
      }
    }
    return acc + precoItem;
  }, 0);

  const oc = await prisma.ordemCompra.create({
    data: {
      ...ordemData,
      usuarioId,
      valorTotal,
      numerosOS: osArray.length
        ? { create: osArray.map((n) => ({ numeroOS: String(n) })) }
        : undefined,
      itens: itensExpandidos.length
        ? {
            create: itensExpandidos.map((item) => {
              const usarM2 = item.usarM2 ?? false;
              // O preço total é a fonte da verdade quando o usuário o
              // define manualmente na tela (ele deriva o preço unitário a
              // partir do total, não o contrário). Recalcular aqui a
              // partir de quantidade/qtdUnidade/precoUnitario amplifica
              // qualquer arredondamento de exibição do preço unitário e
              // faz o total "pular" ao reabrir a OC. Só recalculamos como
              // fallback quando o item não trouxe precoTotal (itens
              // legados/fluxos antigos).
              const precoTotalEnviado = Number(item.precoTotal ?? 0);
              let precoTotal;
              if (precoTotalEnviado > 0) {
                precoTotal = precoTotalEnviado;
              } else if (usarM2 && Number(item.precoMetroQuadrado) > 0) {
                precoTotal = Number(item.quantidade) * Number(item.precoMetroQuadrado);
              } else {
                const precoUnit = Number(item.precoUnitario ?? 0);
                const qtdUnit = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
                if (qtdUnit != null && qtdUnit > 0) {
                  precoTotal = Number(item.quantidade) * qtdUnit * precoUnit;
                } else {
                  precoTotal = Number(item.quantidade) * precoUnit;
                }
              }
              
              return {
                material:           { connect: { id: item.materialId } },
                descricaoItem:      item.descricaoItem?.trim() || null,
                numeroOS:           item.numeroOS,
                quantidade:         Number(item.quantidade),
                qtdUnidade:         item.qtdUnidade != null ? Number(item.qtdUnidade) : null,
                precoUnitario:      usarM2 ? 0 : Number(item.precoUnitario ?? 0),
                precoMetroQuadrado: Number(item.precoMetroQuadrado ?? 0) > 0
                  ? Number(item.precoMetroQuadrado)
                  : 0,
                usarM2,
                precoTotal,
              };
            }),
          }
        : undefined,
    },
    include: {
      itens: {
        include: { material: { select: _selectMaterial } },
      },
      numerosOS: true,
      fornecedor: true,
    },
  });

  await _sincronizarVinculosFornecedor(ordemData.fornecedorId, itensResolvidos);
  return oc;
}

async function atualizar(id, data) {
  const { itens, numerosOS, ...ordemData } = data;

  const ordem = await prisma.ordemCompra.update({ where: { id }, data: ordemData });

  if (Array.isArray(numerosOS)) {
    const osArray = _normalizarNumerosOS(numerosOS);
    await prisma.ordemCompra.update({
      where: { id },
      data: {
        numerosOS: {
          deleteMany: {},
          ...(osArray.length ? { create: osArray.map((n) => ({ numeroOS: String(n) })) } : {}),
        },
      },
    });
  }

  let itensResolvidos = itens;
  if (Array.isArray(itens)) {
    itensResolvidos = await _resolverMateriaisGenericos(itens);
    _validarSemItensDuplicados(itensResolvidos);
    await prisma.ordemCompraItem.deleteMany({ where: { ordemCompraId: id } });
    const itensExpandidos = _expandirItensComDistribuicao(itensResolvidos);
    if (itensExpandidos.length) {
      await prisma.ordemCompraItem.createMany({
        data: itensExpandidos.map((item) => {
          const usarM2 = item.usarM2 ?? false;
          // Mesma regra da criação: respeitar o precoTotal enviado pelo
          // front (fonte da verdade quando editado manualmente) e só
          // recalcular como fallback se ele não vier preenchido — ver
          // comentário equivalente em criar().
          const precoTotalEnviado = Number(item.precoTotal ?? 0);
          let precoTotal;
          if (precoTotalEnviado > 0) {
            precoTotal = precoTotalEnviado;
          } else if (usarM2 && Number(item.precoMetroQuadrado) > 0) {
            precoTotal = Number(item.quantidade) * Number(item.precoMetroQuadrado);
          } else {
            const precoUnit = Number(item.precoUnitario ?? 0);
            const qtdUnit = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
            if (qtdUnit != null && qtdUnit > 0) {
              precoTotal = Number(item.quantidade) * qtdUnit * precoUnit;
            } else {
              precoTotal = Number(item.quantidade) * precoUnit;
            }
          }
          
          return {
            ordemCompraId:      id,
            materialId:         item.materialId,
            descricaoItem:      item.descricaoItem?.trim() || null,
            numeroOS:           item.numeroOS,
            quantidade:         Number(item.quantidade),
            qtdUnidade:         item.qtdUnidade != null ? Number(item.qtdUnidade) : null,
            precoUnitario:      usarM2 ? 0 : Number(item.precoUnitario ?? 0),
            precoMetroQuadrado: Number(item.precoMetroQuadrado ?? 0) > 0
              ? Number(item.precoMetroQuadrado)
              : 0,
            usarM2,
            precoTotal,
          };
        }),
      });
    }
    await recalcularTotal(id);
  }

  const fornecedorIdFinal = ordemData.fornecedorId
    ?? (await prisma.ordemCompra.findUnique({ where: { id }, select: { fornecedorId: true } }))?.fornecedorId;
  await _sincronizarVinculosFornecedor(fornecedorIdFinal, itensResolvidos || []);

  return ordem;
}

async function adicionarItem(ordemCompraId, itemData) {
  const [itemResolvido] = await _resolverMateriaisGenericos([itemData]);
  // `materialGenericoOrigemId` e `materialNomeResolvido` são campos
  // internos de controle (ver _resolverMateriaisGenericos) e não existem
  // no model OrdemCompraItem — precisam ser retirados antes de espalhar o
  // item no `data` do Prisma create, ou a criação falha com
  // "Unknown argument".
  const { materialGenericoOrigemId, materialNomeResolvido, ...itemResolvidoSemOrigem } = itemResolvido;

  // Impede adicionar um material (variante) que a OC já possui — mesma
  // regra aplicada em criar/atualizar via _validarSemItensDuplicados,
  // repetida aqui contra o banco porque este endpoint recebe só 1 item
  // de cada vez, sem ver os itens já salvos na OC.
  if (itemResolvidoSemOrigem.materialId) {
    const jaExiste = await prisma.ordemCompraItem.findFirst({
      where: { ordemCompraId, materialId: itemResolvidoSemOrigem.materialId },
      select: { id: true },
    });
    if (jaExiste) {
      throw {
        status: 400,
        message: materialNomeResolvido
          ? `Item duplicado: "${materialNomeResolvido}" já foi adicionado a esta ordem de compra.`
          : `Item duplicado para o material ${itemResolvidoSemOrigem.materialId}.`,
      };
    }
  }

  const usarM2 = itemResolvidoSemOrigem.usarM2 ?? false;
  // Respeita o precoTotal vindo do front (fonte da verdade quando o
  // usuário o edita manualmente) — só recalcula como fallback se não
  // vier. Ver comentário equivalente em criar()/atualizar().
  const precoTotalEnviado = Number(itemResolvidoSemOrigem.precoTotal ?? 0);
  const precoTotal = precoTotalEnviado > 0
    ? precoTotalEnviado
    : (usarM2 && Number(itemResolvidoSemOrigem.precoMetroQuadrado) > 0
      ? Number(itemResolvidoSemOrigem.quantidade) * Number(itemResolvidoSemOrigem.precoMetroQuadrado)
      : Number(itemResolvidoSemOrigem.quantidade) * Number(itemResolvidoSemOrigem.precoUnitario));

  const dadosItem = {
    ...itemResolvidoSemOrigem,
    usarM2,
    precoUnitario:      usarM2 ? null : (itemResolvidoSemOrigem.precoUnitario ?? null),
    precoMetroQuadrado: Number(itemResolvidoSemOrigem.precoMetroQuadrado ?? 0) > 0
      ? Number(itemResolvidoSemOrigem.precoMetroQuadrado)
      : null,
  };

  const item = await prisma.ordemCompraItem.create({
    data: { ...dadosItem, ordemCompraId, precoTotal },
    include: { material: { select: _selectMaterial } },
  });

  // Mesma sincronização de vínculo fornecedor↔genérico que criar/atualizar
  // já fazem — sem isso, adicionar um item de material genérico direto
  // numa OC já existente (endpoint usado pelo botão "+ item" avulso)
  // deixaria o genérico sem vínculo, igual ao bug original.
  if (materialGenericoOrigemId) {
    const ordem = await prisma.ordemCompra.findUnique({
      where: { id: ordemCompraId },
      select: { fornecedorId: true },
    });
    if (ordem?.fornecedorId) {
      await fornecedorSvc._garantirVinculoGenerico(ordem.fornecedorId, materialGenericoOrigemId);
    }
  }

  await recalcularTotal(ordemCompraId);
  return item;
}

async function removerItem(ordemCompraId, itemId) {
  await prisma.ordemCompraItem.deleteMany({ where: { id: itemId, ordemCompraId } });
  await recalcularTotal(ordemCompraId);
}

async function atualizarItem(itemId, data) {
  const item = await prisma.ordemCompraItem.findUnique({ where: { id: itemId } });

  // Se o materialId estiver sendo alterado para um material genérico
  // (ex.: reaproveitando este endpoint para trocar de material), resolve
  // para o filho concreto do mesmo jeito que em criar/atualizar/adicionarItem.
  let dadosResolvidos = data;
  let materialGenericoOrigemId = null;
  if (data.materialId != null) {
    const [resolvido] = await _resolverMateriaisGenericos([
      { materialId: data.materialId, descricaoItem: data.descricaoItem ?? item.descricaoItem },
    ]);
    dadosResolvidos = { ...data, materialId: resolvido.materialId, descricaoItem: resolvido.descricaoItem };
    materialGenericoOrigemId = resolvido.materialGenericoOrigemId ?? null;

    // Mesma checagem de duplicidade de adicionarItem/criar/atualizar,
    // aqui contra os demais itens já salvos nesta OC (excluindo o
    // próprio item, senão ele sempre "colidiria" consigo mesmo).
    if (resolvido.materialId !== item.materialId) {
      const jaExiste = await prisma.ordemCompraItem.findFirst({
        where: {
          ordemCompraId: item.ordemCompraId,
          materialId: resolvido.materialId,
          id: { not: itemId },
        },
        select: { id: true },
      });
      if (jaExiste) {
        throw {
          status: 400,
          message: resolvido.materialNomeResolvido
            ? `Item duplicado: "${resolvido.materialNomeResolvido}" já foi adicionado a esta ordem de compra.`
            : `Item duplicado para o material ${resolvido.materialId}.`,
        };
      }
    }
  }

  const quantidade    = dadosResolvidos.quantidade    ?? item.quantidade;
  const precoUnitario = dadosResolvidos.precoUnitario ?? item.precoUnitario;
  // Mesma regra: se um precoTotal explícito vier no payload, ele é a
  // fonte da verdade; senão recalcula a partir de quantidade/preço
  // unitário (fallback para chamadas que só ajustam esses dois campos).
  const precoTotalEnviado = Number(dadosResolvidos.precoTotal ?? 0);
  const precoTotal = precoTotalEnviado > 0
    ? precoTotalEnviado
    : Number(quantidade) * Number(precoUnitario);
  const updated = await prisma.ordemCompraItem.update({
    where: { id: itemId },
    data: { ...dadosResolvidos, precoTotal },
  });

  if (materialGenericoOrigemId) {
    const ordem = await prisma.ordemCompra.findUnique({
      where: { id: item.ordemCompraId },
      select: { fornecedorId: true },
    });
    if (ordem?.fornecedorId) {
      await fornecedorSvc._garantirVinculoGenerico(ordem.fornecedorId, materialGenericoOrigemId);
    }
  }

  await recalcularTotal(item.ordemCompraId);
  return updated;
}

async function recalcularTotal(ordemCompraId) {
  const itens = await prisma.ordemCompraItem.findMany({ where: { ordemCompraId } });
  const valorTotal = itens.reduce((acc, i) => acc + Number(i.precoTotal), 0);
  return prisma.ordemCompra.update({ where: { id: ordemCompraId }, data: { valorTotal } });
}

async function finalizar(id, usuarioNome) {
 const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: {
      itens: {
        include: {
          material: true,
        },
      },
      fornecedor: { select: { id: true, nomeFantasia: true } },
    },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'EM_ANDAMENTO') throw { status: 400, message: 'Apenas ordens em andamento podem ser finalizadas' };

  if (!ordem.itens || ordem.itens.length === 0) {
    throw { status: 400, message: 'Não é possível finalizar uma OC sem itens' };
  }

  const numerosOS = [...new Set(ordem.itens.map((i) => i.numeroOS?.trim()).filter(Boolean))];
  const numerosOSNumericas = numerosOS.filter((os) => /^\d+$/.test(os));
  if (numerosOSNumericas.length > 0) {
    const relacoesOSFechadas = await prisma.relacaoOS.findMany({
      where: {
        numeroOS: { in: numerosOSNumericas },
        status: 'FECHADA',
      },
      select: { numeroOS: true },
    });
    if (relacoesOSFechadas.length > 0) {
      const osFechadas = relacoesOSFechadas.map((r) => r.numeroOS).join(', ');
      throw {
        status: 400,
        message: `Não é possível finalizar esta OC: ${relacoesOSFechadas.length === 1 ? 'a OS' : 'as OS'} ${osFechadas} já ${relacoesOSFechadas.length === 1 ? 'foi fechada' : 'foram fechadas'} no controle de estoque. Reabra-${relacoesOSFechadas.length === 1 ? 'a' : 'as'} antes de finalizar.`,
      };
    }
  }

  const itensSemOS = ordem.itens.filter((item) => !item.numeroOS || item.numeroOS.trim() === '');
  if (itensSemOS.length > 0) {
    throw {
      status: 400,
      message: `${itensSemOS.length} ${itensSemOS.length === 1 ? 'item não possui' : 'itens não possuem'} número de OS atribuído. Edite a ordem e atribua uma OS para todos os itens antes de finalizar.`,
    };
  }

  const finalizada = await prisma.ordemCompra.update({
    where: { id },
    data: { status: 'FINALIZADO' },
  });

  for (const item of ordem.itens) {
    if (!item.materialId || !item.material) continue;

    const numeroOSLimpo = item.numeroOS.trim();
    const material      = item.material;
    const osEhNumerica  = /^\d+$/.test(numeroOSLimpo);

    let relacaoOS;

    if (osEhNumerica) {
      relacaoOS = await prisma.relacaoOS.upsert({
        where: { numeroOS: numeroOSLimpo },
        create: {
          numeroOS: numeroOSLimpo,
          status: 'EM_ANDAMENTO',
        },
        update: {},
      });
    } else {
      const _d = new Date();
      const hoje =
        `${String(_d.getDate()).padStart(2, '0')}-` +
        `${String(_d.getMonth() + 1).padStart(2, '0')}-` +
        `${_d.getFullYear()}`;

      const relacaoAberta = await prisma.relacaoOS.findFirst({
        where: {
          status: 'EM_ANDAMENTO',
          OR: [
            { numeroOS: numeroOSLimpo },
            { numeroOS: { startsWith: `${numeroOSLimpo}-${hoje}` } },
          ],
        },
        orderBy: {
          criadoEm: 'asc',
        },
      });

      if (relacaoAberta) {
        relacaoOS = relacaoAberta;
      } else {
        let candidato = `${numeroOSLimpo}-${hoje}`;
        let sufixoSeq = 1;

        while (true) {
          const existente = await prisma.relacaoOS.findUnique({
            where: { numeroOS: candidato },
          });

          if (!existente) {
            relacaoOS = await prisma.relacaoOS.create({
              data: {
                numeroOS: candidato,
                status: 'EM_ANDAMENTO',
              },
            });
            break;
          }

          if (existente.status !== 'FECHADA') {
            relacaoOS = existente;
            break;
          }

          sufixoSeq++;
          candidato = `${numeroOSLimpo}-${hoje}-${sufixoSeq}`;
        }
      }
    }

    const precoUnitarioBruto = Number(item.precoUnitario ?? 0);
    const precoM2Bruto = Number(item.precoMetroQuadrado ?? 0);

    const precoUnitarioFinal = item.usarM2
      ? null
      : _normalizarPreco(precoUnitarioBruto);

    const precoM2Final = item.usarM2
      ? _normalizarPreco(precoM2Bruto)
      : null;

    const novoUltimoValorPago = item.usarM2
      ? null
      : (precoUnitarioFinal ?? null);

    const _larguraMat     = material?.largura     != null ? Number(material.largura)     : null;
    const _comprimentoMat = material?.comprimento != null ? Number(material.comprimento) : null;
    const _areaTotal      = (_larguraMat != null && _comprimentoMat != null && _larguraMat > 0 && _comprimentoMat > 0)
      ? _larguraMat * _comprimentoMat
      : null;

    const _unidade = (material?.unidade ?? '').toString().toLowerCase().trim();
    const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidade);

     const novoUltimoValorPagoM2 = item.usarM2
      ? (precoM2Final ?? null)
      : (() => {
          if (novoUltimoValorPago == null || novoUltimoValorPago <= 0) return null;
          if (_eMetroLinear && _larguraMat != null && _larguraMat > 0) {
            return novoUltimoValorPago / _larguraMat;
          }
          if (_areaTotal != null && _areaTotal > 0) {
            return novoUltimoValorPago / _areaTotal;
          }
          return null;
        })();

    const precoUnitarioMovimentacao = precoUnitarioFinal;

    const quantidadeReal = _calcularQuantidadeReal({
      quantidade: item.quantidade,
      usarM2:     item.usarM2,
      qtdUnidade: item.qtdUnidade,
    });

    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'ENTRADA',
        quantidade:    quantidadeReal,
        numeroOS:      numeroOSLimpo,
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: precoUnitarioMovimentacao,
        precoM2:       item.usarM2 ? precoM2Final : novoUltimoValorPagoM2,
        descricaoItem: item.descricaoItem ?? null,
        observacao:    `Entrada via OC #${id} – ${usuarioNome ?? 'Usuário'}`,
      },
    });

    const matAtual       = await prisma.material.findUnique({ where: { id: item.materialId } });
    const novaQuantidade = Number(matAtual.quantidade) + quantidadeReal;
    const novoStatus     = _calcularStatus(novaQuantidade, matAtual.estoqueMinimo, matAtual.ativo);

    const patchPreco = {};
    if (novoUltimoValorPago !== null || novoUltimoValorPagoM2 !== null) {
      patchPreco.ultimoValorPago   = novoUltimoValorPago;
      patchPreco.ultimoValorPagoM2 = novoUltimoValorPagoM2;
    }

    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade: novaQuantidade,
        status:     novoStatus,
        ...patchPreco,
      },
    });

    await prisma.historicoPrecoMaterial.create({
      data: {
        materialId: item.materialId,
        ordemCompraId: id,
        fornecedorId: ordem.fornecedorId,
        precoUnitario: precoUnitarioMovimentacao,
        precoM2: precoM2Final,
        quantidade: item.quantidade,
        qtdUnidade: item.qtdUnidade != null ? Number(item.qtdUnidade) : null,
        usarM2: item.usarM2 ?? false,
      },
    });
  }

  await _sincronizarVinculosFornecedorPorTotal(ordem.fornecedorId, ordem.itens);

  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data:  { status: 'CONVERTIDO' },
    });
  }

  return finalizada;
}

async function cancelar(id) {
  const ordem = await prisma.ordemCompra.findUnique({ where: { id } });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status === 'FINALIZADO') throw { status: 400, message: 'Ordem finalizada não pode ser cancelada' };
  return prisma.ordemCompra.update({ where: { id }, data: { status: 'CANCELADO' } });
}

async function reverter(id) {
  const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: { itens: { include: { material: true } } },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'FINALIZADO') throw { status: 400, message: 'Apenas ordens finalizadas podem ser revertidas' };

  for (const item of ordem.itens) {
    const material = item.material;
    if (!material || !item.materialId) continue;

    const numeroOSLimpo = item.numeroOS?.trim() || 'OUTROS';

    let relacaoOS = await prisma.relacaoOS.findUnique({ where: { numeroOS: numeroOSLimpo } });
    if (!relacaoOS) {
      relacaoOS = await prisma.relacaoOS.create({ data: { numeroOS: numeroOSLimpo } });
    }

    await prisma.movimentacaoEstoque.deleteMany({
      where: { ordemCompraId: id, materialId: item.materialId },
    });

    await prisma.historicoPrecoMaterial.deleteMany({
      where: { materialId: item.materialId, ordemCompraId: id },
    });

    const historicoAnterior = await prisma.historicoPrecoMaterial.findFirst({
      where:   { materialId: item.materialId },
      orderBy: { criadoEm: 'desc' },
    });

    const quantidadeRealReverter = _calcularQuantidadeReal({
      quantidade: item.quantidade,
      usarM2:     item.usarM2,
      qtdUnidade: item.qtdUnidade,
    });
    // Sem o Math.max(0, ...) que havia aqui: o finalizar soma
    // quantidadeReal sem nenhum piso, então o reverter precisa subtrair
    // do mesmo jeito, sem piso, pra ser a operação inversa exata dele.
    // Se o material já teve saída registrada em Controle de Estoque
    // depois da entrada dada pela OC, a quantidade fica negativa aqui de
    // propósito — é esse "débito" que, ao finalizar de novo, volta pro
    // valor correto. Travar em 0 fazia esse -1 virar 0, e o finalizar
    // seguinte reintroduzia 1 unidade fantasma que já tinha saído do
    // estoque (era esse o bug relatado).
    const novaQuantidade = Number(material.quantidade) - quantidadeRealReverter;
    const novoStatus     = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);
    const anteriorUsarM2 = historicoAnterior?.usarM2 ?? false;
    await prisma.material.update({
      where: { id: item.materialId },
      data: {
        quantidade:        novaQuantidade,
        status:            novoStatus,
        ultimoValorPago:   anteriorUsarM2 ? null : (historicoAnterior?.precoUnitario ?? null),
        ultimoValorPagoM2: anteriorUsarM2 ? (historicoAnterior?.precoM2 ?? null) : null,
      },
    });
  }

  const relacoes = await prisma.relacaoOS.findMany({ include: { movimentacoes: true } });
  for (const relacao of relacoes) {
    if (!relacao.movimentacoes.length) {
      await prisma.relacaoOS.delete({ where: { id: relacao.id } });
    }
  }

  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data:  { status: 'ABERTO' },
    });
  }
  return prisma.ordemCompra.update({ where: { id }, data: { status: 'EM_ANDAMENTO' } });
}

async function criarDeOrcamento(orcamentoId, dadosExtras, usuarioId) {
  const orcamento = await prisma.orcamento.findUnique({
    where: { id: orcamentoId },
    include: {
      itens: {
        include: {
          material:   { select: { id: true, nome: true } },
          fornecedor: true,
        },
      },
    },
  });

  if (!orcamento) throw { status: 404, message: 'Orçamento não encontrado' };

  const {
    fornecedorId, requisitante, formaPagamento, prazoPagamento,
    observacoes, empresa, data, numerosOS,
  } = dadosExtras;

  if (!fornecedorId) {
    throw { status: 400, message: 'Campo obrigatório ausente: fornecedorId' };
  }

  const osNormalizado  = _normalizarNumerosOS(numerosOS);
  const numeroOSPadrao = dadosExtras.numeroOS || osNormalizado[0] || 'OS-GERAL';

  const itens = orcamento.itens.map((item) => ({
    materialId:         item.materialId,
    descricaoItem:      null,
    numeroOS:           item.numeroOS || numeroOSPadrao,
    quantidade:         item.quantidade,
    qtdUnidade:         item.qtdUnidade ?? null,
    precoUnitario:      Number(item.precoUnitario) > 0 ? item.precoUnitario : 0,
    precoMetroQuadrado: null,
    usarM2:             false,
  }));

  return criar({
    fornecedorId:   Number(fornecedorId),
    requisitante:   requisitante?.trim() || 'Não informado',
    formaPagamento: formaPagamento ?? null,
    prazoPagamento: prazoPagamento ?? null,
    observacoes:    observacoes    ?? null,
    empresa:        empresa        ?? null,
    data:           data ? new Date(data) : new Date(),
    status:         'EM_ANDAMENTO',
    orcamentoId,
    numerosOS:      osNormalizado,
    itens,
  }, usuarioId);
}

async function excluir(id) {
  const ordem = await prisma.ordemCompra.findUnique({ where: { id } });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status === 'FINALIZADO') throw { status: 400, message: 'Não é possível excluir uma OC finalizada. Reverta-a primeiro.' };
  return prisma.ordemCompra.delete({ where: { id } });
}

module.exports = {
  listar, listarPagina, contarPorStatus, buscarPorId, criar, atualizar,
  adicionarItem, removerItem, atualizarItem,
  finalizar, cancelar, reverter,
  criarDeOrcamento, excluir,
};