const prisma = require('../utils/prisma');

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
      for (const linha of dist) {
        let precoTotal;
        if (item.usarM2 && Number(item.precoMetroQuadrado) > 0) {
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
      }
    } else {
      resultado.push(item);
    }
  }
  return resultado;
}

const _selectMaterial = {
  id: true,
  nome: true,
  unidade: true,
  medida: true,
  espessura: true,
  identificador: true,
  largura: true,
  comprimento: true,
};

async function _sincronizarVinculosFornecedor(fornecedorId, itens) {
  if (!fornecedorId || !Array.isArray(itens) || itens.length === 0) return;

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
  const itensExpandidos = _expandirItensComDistribuicao(itens || []);

  const valorTotal = itensExpandidos.reduce((acc, item) => {
    let precoItem;
    if (item.usarM2 && Number(item.precoMetroQuadrado) > 0) {
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
              let precoTotal;
              if (usarM2 && Number(item.precoMetroQuadrado) > 0) {
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
                precoMetroQuadrado: usarM2 ? Number(item.precoMetroQuadrado ?? 0) : 0,
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

  await _sincronizarVinculosFornecedor(ordemData.fornecedorId, itens || []);
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

  if (Array.isArray(itens)) {
    await prisma.ordemCompraItem.deleteMany({ where: { ordemCompraId: id } });
    const itensExpandidos = _expandirItensComDistribuicao(itens);
    if (itensExpandidos.length) {
      await prisma.ordemCompraItem.createMany({
        data: itensExpandidos.map((item) => {
          const usarM2 = item.usarM2 ?? false;
          let precoTotal;
          if (usarM2 && Number(item.precoMetroQuadrado) > 0) {
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
            precoMetroQuadrado: usarM2 ? Number(item.precoMetroQuadrado ?? 0) : 0,
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
  await _sincronizarVinculosFornecedor(fornecedorIdFinal, itens || []);

  return ordem;
}

async function adicionarItem(ordemCompraId, itemData) {
  const usarM2     = itemData.usarM2 ?? false;
  const precoTotal = usarM2 && Number(itemData.precoMetroQuadrado) > 0
    ? Number(itemData.quantidade) * Number(itemData.precoMetroQuadrado)
    : Number(itemData.quantidade) * Number(itemData.precoUnitario);

  const dadosItem = {
    ...itemData,
    usarM2,
    precoUnitario:      usarM2 ? null : (itemData.precoUnitario ?? null),
    precoMetroQuadrado: usarM2 ? (itemData.precoMetroQuadrado ?? null) : null,
  };

  const item = await prisma.ordemCompraItem.create({
    data: { ...dadosItem, ordemCompraId, precoTotal },
    include: { material: { select: _selectMaterial } },
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
  const quantidade    = data.quantidade    ?? item.quantidade;
  const precoUnitario = data.precoUnitario ?? item.precoUnitario;
  const precoTotal    = Number(quantidade) * Number(precoUnitario);
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
    const novaQuantidade = Math.max(0, Number(material.quantidade) - quantidadeRealReverter);
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
  listar, buscarPorId, criar, atualizar,
  adicionarItem, removerItem, atualizarItem,
  finalizar, cancelar, reverter,
  criarDeOrcamento, excluir,
};