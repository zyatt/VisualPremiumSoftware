const prisma = require('../utils/prisma');

/**
 * Normaliza valores de preço: converte 0 para null (ausência de informação)
 */
function _normalizarPreco(valor) {
  if (valor == null) return null;
  const num = Number(valor);
  return num > 0 ? num : null;
}

/**
 * Normaliza o campo numerosOS independente do formato recebido.
 */
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

async function listar(status) {
  const where = {};
  if (status) where.status = status;
  return prisma.ordemCompra.findMany({
    where,
    include: {
      fornecedor: { select: { id: true, nomeFantasia: true } },
      usuario:    { select: { id: true, nome: true } },
      itens: {
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              unidade: true,
              especifico: true,
              medida: true,
              espessura: true,
              identificador: true,
            },
          },
        },
      },
      numerosOS: true,
    },
    orderBy: { criadoEm: 'desc' },
  });
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

  const valorTotal = (itens || []).reduce((acc, item) => {
    const precoBase = item.usarM2 && Number(item.precoMetroQuadrado) > 0
      ? Number(item.precoMetroQuadrado)
      : Number(item.precoUnitario);
    return acc + Number(item.quantidade) * precoBase;
  }, 0);

  return prisma.ordemCompra.create({
    data: {
      ...ordemData,
      usuarioId,
      valorTotal,
      numerosOS: osArray.length
        ? { create: osArray.map((n) => ({ numeroOS: String(n) })) }
        : undefined,
      itens: itens?.length
        ? {
            create: itens.map((item) => {
              const usarM2 = item.usarM2 ?? false;
              return {
                material:           { connect: { id: item.materialId } },
                descricaoItem:      item.descricaoItem?.trim() || null,
                numeroOS:           item.numeroOS,
                quantidade:         Number(item.quantidade),
                // Campos não-nullable no schema: usar 0 quando o campo não se aplica
                precoUnitario:      usarM2 ? 0 : Number(item.precoUnitario ?? 0),
                precoMetroQuadrado: usarM2 ? Number(item.precoMetroQuadrado ?? 0) : 0,
                usarM2,
                precoTotal:         usarM2 && Number(item.precoMetroQuadrado) > 0
                  ? Number(item.quantidade) * Number(item.precoMetroQuadrado)
                  : Number(item.quantidade) * Number(item.precoUnitario ?? 0),
              };
            }),
          }
        : undefined,
    },
    include: {
      itens: {
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              unidade: true,
              especifico: true,
              medida: true,
              espessura: true,
              identificador: true,
            },
          },
        },
      },
      numerosOS: true,
      fornecedor: true,
    },
  });
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

  if (Array.isArray(itens)) {
    await prisma.ordemCompraItem.deleteMany({ where: { ordemCompraId: id } });
    if (itens.length) {
      await prisma.ordemCompraItem.createMany({
        data: itens.map((item) => {
          const usarM2 = item.usarM2 ?? false;
          return {
            ordemCompraId:      id,
            materialId:         item.materialId,
            descricaoItem:      item.descricaoItem?.trim() || null,
            numeroOS:           item.numeroOS,
            quantidade:         Number(item.quantidade),
            // Campos não-nullable no schema: usar 0 quando o campo não se aplica
            precoUnitario:      usarM2 ? 0 : Number(item.precoUnitario ?? 0),
            precoMetroQuadrado: usarM2 ? Number(item.precoMetroQuadrado ?? 0) : 0,
            usarM2,
            precoTotal:         usarM2 && Number(item.precoMetroQuadrado) > 0
              ? Number(item.quantidade) * Number(item.precoMetroQuadrado)
              : Number(item.quantidade) * Number(item.precoUnitario ?? 0),
          };
        }),
      });
    }
    await recalcularTotal(id);
  }

  return ordem;
}

async function adicionarItem(ordemCompraId, itemData) {
  const usarM2     = itemData.usarM2 ?? false;
  const precoTotal = usarM2 && Number(itemData.precoMetroQuadrado) > 0
    ? Number(itemData.quantidade) * Number(itemData.precoMetroQuadrado)
    : Number(itemData.quantidade) * Number(itemData.precoUnitario);

  // Garante que o campo não-escolhido seja null
  const dadosItem = {
    ...itemData,
    usarM2,
    precoUnitario:      usarM2 ? null : (itemData.precoUnitario ?? null),
    precoMetroQuadrado: usarM2 ? (itemData.precoMetroQuadrado ?? null) : null,
  };

  const item = await prisma.ordemCompraItem.create({
    data: { ...dadosItem, ordemCompraId, precoTotal },
    include: {
      material: {
        select: {
          id: true,
          nome: true,
          unidade: true,
          especifico: true,
          medida: true,
          espessura: true,
          identificador: true,
        },
      },
    },
  });
  await recalcularTotal(ordemCompraId);
  return item;
}

async function removerItem(ordemCompraId, itemId) {
  await prisma.ordemCompraItem.deleteMany({ where: { id: itemId, ordemCompraId } });
  await recalcularTotal(ordemCompraId);
}

async function atualizarItem(itemId, data) {
  const item = await prisma.ordemCompraItem.findUnique({ where: { id: itemId } });
  const quantidade     = data.quantidade    ?? item.quantidade;
  const precoUnitario  = data.precoUnitario ?? item.precoUnitario;
  const precoTotal     = Number(quantidade) * Number(precoUnitario);
  const updated = await prisma.ordemCompraItem.update({
    where: { id: itemId },
    data: { ...data, precoTotal },
  });
  await recalcularTotal(item.ordemCompraId);
  return updated;
}

async function recalcularTotal(ordemCompraId) {
  const itens = await prisma.ordemCompraItem.findMany({ where: { ordemCompraId } });
  const valorTotal = itens.reduce((acc, i) => acc + Number(i.precoTotal), 0);
  return prisma.ordemCompra.update({ where: { id: ordemCompraId }, data: { valorTotal } });
}

// ─────────────────────────────────────────────────────────────────────────────
// FINALIZAR
// ─────────────────────────────────────────────────────────────────────────────
async function finalizar(id) {
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

  // ── Valida que nenhuma OS da OC está fechada no controle de estoque ──────
  const numerosOS = [...new Set(ordem.itens.map((i) => i.numeroOS?.trim()).filter(Boolean))];
  if (numerosOS.length > 0) {
    const relacoesOSFechadas = await prisma.relacaoOS.findMany({
      where: {
        numeroOS: { in: numerosOS },
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
  // ─────────────────────────────────────────────────────────────────────────

  const itensSemOS = ordem.itens.filter((item) => !item.numeroOS || item.numeroOS.trim() === '');
  if (itensSemOS.length > 0) {
    throw {
      status: 400,
      message: `${itensSemOS.length} ${itensSemOS.length === 1 ? 'item não possui' : 'itens não possuem'} número de OS atribuído. Edite a ordem e atribua uma OS para todos os itens antes de finalizar.`,
    };
  }

  // Valida que itens de material específico possuem descricaoItem
  const itensSemDescricao = ordem.itens.filter(
    (item) => item.material?.especifico && (!item.descricaoItem || !item.descricaoItem.trim())
  );
  if (itensSemDescricao.length > 0) {
    const nomes = itensSemDescricao.map((i) => i.material?.nome || `ID ${i.materialId}`).join(', ');
    throw {
      status: 400,
      message: `Os seguintes materiais específicos exigem uma descrição: ${nomes}`,
    };
  }

  const finalizada = await prisma.ordemCompra.update({
    where: { id },
    data: { status: 'FINALIZADO' },
  });

  // Mapa para reutilizar a mesma RelacaoOS dentro desta OC (para OS textuais)
  // OS numérica → busca/cria única pelo numeroOS (mescla entre OCs)
  // OS textual  → cria sempre uma nova por OC, reutilizando dentro da mesma OC
  const relacaoOSPorOC = new Map(); // chave: numeroOS (apenas para textuais, dentro desta OC)

  for (const item of ordem.itens) {
    const numeroOSLimpo = item.numeroOS.trim();
    const material      = item.material;
    const eEspecifico   = material?.especifico === true;

    const osEhNumerica = /^\d+$/.test(numeroOSLimpo);

    let relacaoOS;

    if (osEhNumerica) {
      // OS numérica → mescla na RelacaoOS existente entre OCs
      relacaoOS = await prisma.relacaoOS.findUnique({
        where: { numeroOS: numeroOSLimpo },
      });
      if (!relacaoOS) {
        relacaoOS = await prisma.relacaoOS.create({
          data: { numeroOS: numeroOSLimpo },
        });
      }
    } else {
      // OS textual → sempre cria uma nova RelacaoOS por OC
      // Reutiliza a que foi criada para esta OS dentro desta mesma OC
      if (relacaoOSPorOC.has(numeroOSLimpo)) {
        relacaoOS = relacaoOSPorOC.get(numeroOSLimpo);
      } else {
        // Gera um sufixo único para evitar conflito de unique constraint no numeroOS
        relacaoOS = await prisma.relacaoOS.create({
          data: { numeroOS: `${numeroOSLimpo}#OC${id}` },
        });
        relacaoOSPorOC.set(numeroOSLimpo, relacaoOS);
      }
    }

    // Lê os preços brutos do item (sem normalizar para null ainda, para não perder zeros)
    const precoUnitarioBruto = Number(item.precoUnitario      ?? 0);
    const precoM2Bruto       = Number(item.precoMetroQuadrado ?? 0);

    // Determina qual campo é o "efetivo" conforme usarM2
    // _normalizarPreco converte 0 → null (ausência de informação)
    const precoUnitarioFinal = item.usarM2 ? null : _normalizarPreco(precoUnitarioBruto);
    const precoM2Final       = item.usarM2 ? _normalizarPreco(precoM2Bruto) : null;

    // Para o ultimoValorPago: usa o valor efetivo (nunca sobrescreve com null quando há preço)
    const novoUltimoValorPago   = item.usarM2 ? null : (precoUnitarioFinal ?? null);
    const novoUltimoValorPagoM2 = item.usarM2 ? (precoM2Final ?? null) : null;

    // Cria movimentação (igual para específico e não-específico; descricaoItem já está no item)
    // numeroOS na movimentação sempre usa o valor original (sem sufixo interno da RelacaoOS)
    await prisma.movimentacaoEstoque.create({
      data: {
        materialId:    item.materialId,
        tipo:          'ENTRADA',
        quantidade:    item.quantidade,
        numeroOS:      numeroOSLimpo,   // valor original sem sufixo
        relacaoOSId:   relacaoOS.id,
        ordemCompraId: id,
        precoUnitario: precoUnitarioFinal,
        precoM2:       precoM2Final,
        descricaoItem: item.descricaoItem ?? null,
        observacao:    `Entrada via OC #${id}`,
      },
    });

    if (eEspecifico) {
      // ── Material específico: acumula em EstoqueEspecifico, NÃO altera material.quantidade ──
      const descricao = item.descricaoItem.trim();
      await prisma.estoqueEspecifico.upsert({
        where:  { materialId_descricao: { materialId: item.materialId, descricao } },
        create: { materialId: item.materialId, descricao, quantidade: item.quantidade },
        update: { quantidade: { increment: Number(item.quantidade) } },
      });
      // Atualiza ultimoValorPago somente se o item trouxe preço efetivo
      if (novoUltimoValorPago !== null || novoUltimoValorPagoM2 !== null) {
        await prisma.material.update({
          where: { id: item.materialId },
          data: {
            ultimoValorPago:   novoUltimoValorPago,
            ultimoValorPagoM2: novoUltimoValorPagoM2,
          },
        });
      }
    } else {
      // ── Material normal: atualiza material.quantidade ──
      const matAtual = await prisma.material.findUnique({ where: { id: item.materialId } });
      const novaQuantidade = Number(matAtual.quantidade) + Number(item.quantidade);
      const novoStatus     = _calcularStatus(novaQuantidade, matAtual.estoqueMinimo, matAtual.ativo);

      // Monta o patch de preço: só sobrescreve se o item trouxe preço efetivo
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
    }

    // Histórico de preços (para todos)
    await prisma.historicoPrecoMaterial.create({
      data: {
        materialId:    item.materialId,
        ordemCompraId: id,
        fornecedorId:  ordem.fornecedorId,
        precoUnitario: precoUnitarioFinal,
        precoM2:       precoM2Final,
        quantidade:    item.quantidade,
        usarM2:        item.usarM2 ?? false,
      },
    });
  }

  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data:  { status: 'CONVERTIDO' },
    });
  }

  return finalizada;
}

// ─────────────────────────────────────────────────────────────────────────────
// CANCELAR
// ─────────────────────────────────────────────────────────────────────────────
async function cancelar(id) {
  const ordem = await prisma.ordemCompra.findUnique({ where: { id } });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status === 'FINALIZADO') throw { status: 400, message: 'Ordem finalizada não pode ser cancelada' };
  return prisma.ordemCompra.update({ where: { id }, data: { status: 'CANCELADO' } });
}

// ─────────────────────────────────────────────────────────────────────────────
// REVERTER
// ─────────────────────────────────────────────────────────────────────────────
async function reverter(id) {
  const ordem = await prisma.ordemCompra.findUnique({
    where: { id },
    include: { itens: { include: { material: true } } },
  });
  if (!ordem) throw { status: 404, message: 'Ordem de compra não encontrada' };
  if (ordem.status !== 'FINALIZADO') throw { status: 400, message: 'Apenas ordens finalizadas podem ser revertidas' };

  for (const item of ordem.itens) {
    const material    = item.material;
    if (!material) continue;

    const eEspecifico = material.especifico === true;

    const numeroOSLimpo = item.numeroOS?.trim() || 'OUTROS';

    const osEhNumerica = /^\d+$/.test(numeroOSLimpo);

    let relacaoOS = await prisma.relacaoOS.findUnique({
      where: {
        numeroOS: numeroOSLimpo,
      },
    });

    if (!relacaoOS) {
      relacaoOS = await prisma.relacaoOS.create({
        data: {
          numeroOS: numeroOSLimpo,
        },
      });
    }
    const precoUnitarioValor = _normalizarPreco(item.precoUnitario);
    const precoM2Valor       = _normalizarPreco(item.precoMetroQuadrado);

    // Usa apenas o campo registrado na OC (baseado em usarM2 do item)
    const precoUnitarioEstorno = item.usarM2 ? null : precoUnitarioValor;
    const precoM2Estorno       = item.usarM2 ? precoM2Valor : null;

    // Movimentação de estorno (SAIDA)
    await prisma.movimentacaoEstoque.deleteMany({
      where: {
        ordemCompraId: id,
        materialId: item.materialId,
      },
    });

    // ── Remove histórico de preços desta OC (vale para específico e normal) ──
    await prisma.historicoPrecoMaterial.deleteMany({
      where: { materialId: item.materialId, ordemCompraId: id },
    });

    // Registro mais recente que restou após a remoção (para restaurar ultimoValorPago)
    const historicoAnterior = await prisma.historicoPrecoMaterial.findFirst({
      where:   { materialId: item.materialId },
      orderBy: { criadoEm: 'desc' },
    });

    if (eEspecifico) {
      // ── Material específico: decrementa o filho em EstoqueEspecifico ──
      const descricao = (item.descricaoItem ?? '').trim();
      if (descricao) {
        const filho = await prisma.estoqueEspecifico.findUnique({
          where: { materialId_descricao: { materialId: item.materialId, descricao } },
        });
        if (filho) {
          const novaQtd = Math.max(0, Number(filho.quantidade) - Number(item.quantidade));
          if (novaQtd === 0) {
            await prisma.estoqueEspecifico.delete({
              where: { materialId_descricao: { materialId: item.materialId, descricao } },
            });
          } else {
            await prisma.estoqueEspecifico.update({
              where: { materialId_descricao: { materialId: item.materialId, descricao } },
              data:  { quantidade: novaQtd },
            });
          }
        }
      }
      // Restaura ultimoValorPago no material específico:
      // usa apenas o campo que o histórico anterior registrou (baseado em usarM2)
      const anteriorUsarM2 = historicoAnterior?.usarM2 ?? false;
      await prisma.material.update({
        where: { id: item.materialId },
        data: {
          ultimoValorPago:   anteriorUsarM2 ? null : (historicoAnterior?.precoUnitario ?? null),
          ultimoValorPagoM2: anteriorUsarM2 ? (historicoAnterior?.precoM2 ?? null) : null,
        },
      });
    } else {
      // ── Material normal: decrementa material.quantidade ──
      const novaQuantidade = Math.max(0, Number(material.quantidade) - Number(item.quantidade));
      const novoStatus     = _calcularStatus(novaQuantidade, material.estoqueMinimo, material.ativo);

      // Restaura apenas o campo que o histórico anterior registrou
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
  }

  const relacoes = await prisma.relacaoOS.findMany({
    include: {
      movimentacoes: true,
    },
  });

  for (const relacao of relacoes) {
    if (!relacao.movimentacoes.length) {
      await prisma.relacaoOS.delete({
        where: {
          id: relacao.id,
        },
      });
    }
  }

  if (ordem.orcamentoId) {
    await prisma.orcamento.update({
      where: { id: ordem.orcamentoId },
      data: {
        status: "ABERTO"  // ✅ era "PENDENTE", que não existe no enum
      }
    });
  }
  return prisma.ordemCompra.update({
    where: { id },
    data:  { status: 'EM_ANDAMENTO' },
  });
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
  listar, buscarPorId, criar, atualizar,
  adicionarItem, removerItem, atualizarItem,
  finalizar, cancelar, reverter,
  criarDeOrcamento, excluir,
};