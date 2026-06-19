const prisma = require('../utils/prisma');

// ── include reutilizável ──────────────────────────────────────────────────────
const _includeMovimentacoes = {
  movimentacoes: {
    include: {
      material: {
        select: {
          id: true, nome: true, unidade: true,
          identificador: true, medida: true, espessura: true,
          especifico: true, qtdPadrao: true, unidPadrao: true,
        },
      },
    },
    orderBy: { criadoEm: 'desc' },
  },
};

// ── Controle de Estoque: apenas OS EM_ANDAMENTO ───────────────────────────────
async function listarEmAndamento(busca) {
  const where = { status: 'EM_ANDAMENTO' };
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: _includeMovimentacoes,
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarPorNumeroOS(numeroOS) {
  return prisma.relacaoOS.findFirst({
    where:   { numeroOS },
    orderBy: { criadoEm: 'desc' },
    include: _includeMovimentacoes,
  });
}

// ── Registrar movimentação ────────────────────────────────────────────────────
async function registrarMovimentacao({
  materialId, tipo, quantidade, numeroOS,
  precoUnitario, precoM2, observacao, ordemCompraId, descricaoItem,
  // Dimensões usadas na saída (apenas para materiais UNIDADE com largura/comprimento)
  larguraUsada, comprimentoUsado,
  // Nome do usuário autenticado que registrou a movimentação
  usuarioNome,
}) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material) throw { status: 404, message: 'Material não encontrado' };
  
  const osEhNumerica = /^\d+$/.test(numeroOS);
  const osTemSufixo  = /#(OC|S|E)/.test(numeroOS);
  // Verifica se OS não está fechada (busca a mais recente com esse numeroOS)
  if (osEhNumerica) {
    const relacaoExistente = await prisma.relacaoOS.findFirst({
      where: { numeroOS },
      orderBy: { criadoEm: 'desc' },
    });

    if (relacaoExistente?.status === 'FECHADA') {
      throw {
        status: 400,
        message: `A OS ${numeroOS} está fechada e não aceita novas movimentações`,
      };
    }
  }

  // Material específico: descricaoItem obrigatória
  if (material.especifico) {
    const desc = (descricaoItem ?? '').trim();
    if (!desc) {
      throw { status: 400, message: 'Materiais específicos exigem uma descrição para movimentação de estoque' };
    }
  }

  if (tipo === 'SAIDA') {
    if (material.especifico) {
      // Verifica saldo do filho específico
      const desc  = (descricaoItem ?? '').trim();
      const filho = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId, descricao: desc } },
      });
      const saldoFilho = filho ? Number(filho.quantidade) : 0;
      if (saldoFilho < quantidade) {
        throw {
          status: 400,
          message: `Estoque insuficiente para "${desc}": disponível ${saldoFilho} ${material.unidade ?? ''}`.trim(),
        };
      }
    } else {
      const saldo = Number(material.quantidade);
      if (saldo < quantidade) {
        throw {
          status: 400,
          message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
        };
      }
    }
  }

  const delta = tipo === 'ENTRADA' ? quantidade : -quantidade;

  // Resolve qual RelacaoOS usar:
  // 1. OS numérica ou com sufixo (#OC/#S/#E): upsert direto pelo numeroOS exato.
  // 2. OS textual sem sufixo: verifica se já existe uma RelacaoOS EM_ANDAMENTO
  //    com esse numeroOS (ex: criada pela produção). Se existir, reutiliza.
  //    Só cria nova com sufixo de timestamp quando não houver nenhuma aberta.
  
  let relacao;

  if (osEhNumerica || osTemSufixo) {
    // OS numérica ou com sufixo: upsert garante uma única relação por chave exata
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    // OS textual sem sufixo: tenta reutilizar RelacaoOS EM_ANDAMENTO existente
    // (inclui a OS com o nome exato OU com sufixo de data do dia de hoje)
    const _d   = new Date();
    const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`; // "DD-MM-YYYY"

    const relacaoAberta = await prisma.relacaoOS.findFirst({
      where: {
        status:   'EM_ANDAMENTO',
        OR: [
          { numeroOS: numeroOS },
          { numeroOS: { startsWith: `${numeroOS}-${hoje}` } },
        ],
      },
      orderBy: { criadoEm: 'asc' },
    });

    if (relacaoAberta) {
      // Já existe uma OS aberta com esse nome (ou com sufixo de data de hoje) — reutiliza
      relacao = relacaoAberta;
    } else {
      // Não existe nenhuma aberta: cria nova com sufixo de data (mesmo padrão do producao_service)
      let candidato  = `${numeroOS}-${hoje}`;
      let sufixoSeq  = 1;

      while (true) {
        const existente = await prisma.relacaoOS.findUnique({ where: { numeroOS: candidato } });
        if (!existente) {
          relacao = await prisma.relacaoOS.create({ data: { numeroOS: candidato, status: 'EM_ANDAMENTO' } });
          break;
        }
        if (existente.status !== 'FECHADA') {
          relacao = existente;
          break;
        }
        sufixoSeq += 1;
        candidato = `${numeroOS}-${hoje}-${sufixoSeq}`;
      }
    }
  }
  // ── Custo por unidade menor ───────────────────────────────────────────────
  // Se o material tem qtdPadrao (ex: thinner 18 L = 18000 ml), o precoUnitario
  // registrado no estoque deve ser o custo por unidade menor (R$/ml, R$/m etc.).
  // O front envia o precoUnitarioSugerido que já vem do campo ultimoValorPago
  // do material — que é o custo por unidade menor gravado pela OC.
  // Portanto, para movimentações manuais, apenas repassamos o valor sem alterar.
  // O único ajuste necessário é: se o front ainda não tiver o custo por unidade
  // menor disponível (ex: primeiro uso, sem OC prévia) e enviar o preço de
  // embalagem com o flag `precoEhEmbalagem: true`, aí dividimos aqui.
  // Na prática, o front passa item.precoUnitarioSugerido = material.ultimoValorPago
  // que a OC já gravou como custo/unidade — logo não é necessário dividir novamente.
  const precoUnitarioFinal = precoUnitario ?? null;

  // ── Custo proporcional por dimensão usada ─────────────────────────────────
  // Apenas para materiais UNIDADE (chapa/peça) com dimensões cadastradas,
  // quando o usuário informa larguraUsada × comprimentoUsado.
  //
  // Materiais metro linear (m, m/l…) NÃO passam por aqui: o front já envia
  // precoM2 = custoM2 × largura (custo por metro linear), e o relatório calcula
  // custo total = quantidade(metros) × precoM2. Não há segunda multiplicação.
  //
  // Para chapas, a fórmula é:
  //   areaUsada     = larguraUsada × comprimentoUsado
  //   custoM2       = precoM2 do material (R$/m²)
  //   precoM2Final  = custoM2 × areaUsada   (custo total desta saída)
  //
  // Como a quantidade é sempre 1 UNIDADE, salvar o custo total como precoM2
  // garante que quantidade(1) × precoM2Final = custo real no relatório.
  const _unidadeMat = (material.unidade ?? '').toLowerCase().trim();
  const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidadeMat);

  let precoM2Final = precoM2 ?? null;
  if (
    tipo === 'SAIDA' &&
    !_eMetroLinear &&
    larguraUsada != null && comprimentoUsado != null &&
    material.largura != null && material.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaUsada = larg * comp;
      const areaTotal = largTotal * compTotal;
      // Custo por m²: usa precoM2 enviado, senão deriva do precoUnitario ÷ areaTotal
      const custoM2 = precoM2 != null
        ? Number(precoM2)
        : (precoUnitario != null && areaTotal > 0
            ? Number(precoUnitario) / areaTotal
            : null);
      if (custoM2 != null) {
        // Arredonda para 5 casas decimais (precisão do campo Decimal(15,5))
        precoM2Final = Math.round(custoM2 * areaUsada * 100000) / 100000;
      }
    }
  }

  // Monta observação: usa a que veio do front, ou gera automaticamente com o nome do usuário
  const obsFinal = (observacao && observacao.trim())
    ? observacao.trim()
    : `${tipo === 'SAIDA' ? 'Saída' : 'Entrada'} via controle de estoque – ${usuarioNome ?? 'Usuário'}`;

  // Cria a movimentação
  const [movimentacao] = await prisma.$transaction([
    prisma.movimentacaoEstoque.create({
      data: {
        materialId,
        tipo,
        quantidade,
        numeroOS,
        relacaoOSId:      relacao.id,
        precoUnitario:    precoUnitarioFinal,
        precoM2:          precoM2Final,
        observacao:       obsFinal,
        ordemCompraId:    ordemCompraId ?? null,
        descricaoItem:    descricaoItem ?? null,
        larguraUsada:     (larguraUsada    != null ? Number(larguraUsada)    : null),
        comprimentoUsado: (comprimentoUsado != null ? Number(comprimentoUsado) : null),
      },
    }),
    // Para material normal: atualiza quantidade direta; para específico: será feito abaixo
    ...(material.especifico
      ? []
      : [
          prisma.material.update({
            where: { id: materialId },
            data:  { quantidade: { increment: delta } },
          }),
        ]),
  ]);

  if (material.especifico) {
    // Atualiza ou cria filho em EstoqueEspecifico
    const desc = (descricaoItem ?? '').trim();
    if (tipo === 'ENTRADA') {
      await prisma.estoqueEspecifico.upsert({
        where:  { materialId_descricao: { materialId, descricao: desc } },
        create: { materialId, descricao: desc, quantidade },
        update: { quantidade: { increment: Number(quantidade) } },
      });
    } else {
      const filho    = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId, descricao: desc } },
      });
      const novaQtd  = Math.max(0, Number(filho?.quantidade ?? 0) - Number(quantidade));
      if (novaQtd === 0) {
        await prisma.estoqueEspecifico.delete({
          where: { materialId_descricao: { materialId, descricao: desc } },
        });
      } else {
        await prisma.estoqueEspecifico.update({
          where: { materialId_descricao: { materialId, descricao: desc } },
          data:  { quantidade: novaQtd },
        });
      }
    }
    // Não recalcula status de material específico (ele não tem quantidade própria)
  } else {
    // Recalcula status do material normal
    const atualizado = await prisma.material.findUnique({ where: { id: materialId } });
    const novoStatus = _calcularStatus(atualizado.quantidade, atualizado.estoqueMinimo, atualizado.ativo);
    await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });
  }

  // ── Retalho ───────────────────────────────────────────────────────────────
  // Quando o usuário informa dimensão usada numa saída de material UNIDADE,
  // a área restante (areaTotal − areaUsada) é creditada diretamente no
  // cadastro do material retalho — sem criar movimentação de estoque.
  // O retalho é identificado por: mesmo nome + identificador 'RETALHO' + espessura.
  if (
    tipo === 'SAIDA' &&
    !material.especifico &&
    larguraUsada != null && comprimentoUsado != null &&
    material.largura != null && material.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaTotal   = largTotal * compTotal;
      const areaUsada   = larg * comp;
      const areaRetalho = Math.round((areaTotal - areaUsada) * 10000) / 10000;

      if (areaRetalho > 0.0001) {
        // Busca material retalho existente: mesmo nome + 'RETALHO' + espessura
        let retalhoMat = await prisma.material.findFirst({
          where: {
            nome:          { equals: material.nome, mode: 'insensitive' },
            identificador: { equals: 'RETALHO',    mode: 'insensitive' },
            espessura:     material.espessura
              ? { equals: material.espessura, mode: 'insensitive' }
              : null,
          },
        });

        // Custo por m² do retalho:
        // Se o material tem precoM2 enviado na movimentação → usa direto.
        // Caso contrário, deriva do preço unitário ÷ área total da chapa.
        // O retalho é sempre em M2, portanto NÃO copia ultimoValorPago (unitário).
        const custoM2Retalho = (() => {
          // precoM2 no escopo desta saída (calculado acima)
          if (precoM2Final != null && precoM2Final > 0) {
            // precoM2Final já é o custo proporcional da área usada —
            // precisamos do custo *por m²*, não do total da saída.
            // Como precoM2Final = custoM2 × areaUsada, revertemos:
            const areaUsada = Number(larguraUsada) * Number(comprimentoUsado);
            if (areaUsada > 0) return precoM2Final / areaUsada;
          }
          // Tenta derivar do precoUnitario ÷ areaTotal
          const pu = precoUnitario != null ? Number(precoUnitario) : null;
          const areaT = Number(material.largura) * Number(material.comprimento);
          if (pu != null && pu > 0 && areaT > 0) return pu / areaT;
          // Último recurso: valor já gravado no material
          return material.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;
        })();

        if (!retalhoMat) {
          // Cria o material retalho — a quantidade já nasce com areaRetalho
          try {
            retalhoMat = await prisma.material.create({
              data: {
                nome:              material.nome,
                unidade:           'M2',
                categoria:         material.categoria   ?? null,
                medida:            material.medida      ?? null,
                espessura:         material.espessura   ?? null,
                identificador:     'RETALHO',
                quantidade:        areaRetalho,
                estoqueMinimo:     0,
                status:            _calcularStatus(areaRetalho, 0, true),
                estoqueConfirmado: false,
                ativo:             true,
                especifico:        false,
                // Retalho é medido em M2: apenas custo/m² faz sentido
                ultimoValorPago:   null,
                ultimoValorPagoM2: custoM2Retalho,
              },
            });
          } catch (err) {
            // Unique constraint [nome, medida, espessura]: já existe material com
            // esse nome/medida/espessura mas identificador diferente de 'RETALHO'.
            // Recupera e incrementa a quantidade nele.
            if (err?.code === 'P2002') {
              retalhoMat = await prisma.material.findFirst({
                where: {
                  nome:      { equals: material.nome, mode: 'insensitive' },
                  medida:    material.medida
                    ? { equals: material.medida,    mode: 'insensitive' }
                    : null,
                  espessura: material.espessura
                    ? { equals: material.espessura, mode: 'insensitive' }
                    : null,
                },
              });
              if (!retalhoMat) throw err;
              const novaQtd = Number(retalhoMat.quantidade) + areaRetalho;
              await prisma.material.update({
                where: { id: retalhoMat.id },
                data: {
                  quantidade: novaQtd,
                  status:     _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
                },
              });
            } else {
              throw err;
            }
          }
        } else {
          // Retalho já existe — incrementa quantidade, recalcula status
          // e atualiza custo/m² se temos um valor calculado
          const novaQtd = Number(retalhoMat.quantidade) + areaRetalho;
          await prisma.material.update({
            where: { id: retalhoMat.id },
            data: {
              quantidade:        novaQtd,
              status:            _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
              ultimoValorPago:   null, // retalho é M2, não tem custo unitário
              ...(custoM2Retalho != null ? { ultimoValorPagoM2: custoM2Retalho } : {}),
            },
          });
        }
      }
    }
  }

  return movimentacao;
}

async function removerMovimentacao(movimentacaoId) {
  const mov = await prisma.movimentacaoEstoque.findUnique({ where: { id: movimentacaoId } });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };

  // Busca a relação pelo id que está na própria movimentação (sempre preciso)
  const relacao = await prisma.relacaoOS.findUnique({ where: { id: mov.relacaoOSId } });
  if (relacao?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível remover movimentações de uma OS fechada' };
  }

  const material = await prisma.material.findUnique({ where: { id: mov.materialId } });

  // Reverte o delta
  const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

  if (material?.especifico) {
    // Reverte no filho EstoqueEspecifico
    await prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } });

    const desc = (mov.descricaoItem ?? '').trim();
    if (desc) {
      const filho   = await prisma.estoqueEspecifico.findUnique({
        where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
      });
      const novaQtd = Math.max(0, Number(filho?.quantidade ?? 0) + delta);
      if (novaQtd === 0) {
        await prisma.estoqueEspecifico.delete({
          where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
        });
      } else {
        await prisma.estoqueEspecifico.upsert({
          where:  { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
          create: { materialId: mov.materialId, descricao: desc, quantidade: Math.max(0, delta) },
          update: { quantidade: novaQtd },
        });
      }
    }
  } else {
    await prisma.$transaction([
      prisma.movimentacaoEstoque.delete({ where: { id: movimentacaoId } }),
      prisma.material.update({
        where: { id: mov.materialId },
        data:  { quantidade: { increment: delta } },
      }),
    ]);

    const mat      = await prisma.material.findUnique({ where: { id: mov.materialId } });
    const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
    await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
  }

  // Se a RelacaoOS ficou sem movimentações, exclui ela
  const count = await prisma.movimentacaoEstoque.count({ where: { relacaoOSId: relacao.id } });
  if (count === 0) {
    await prisma.relacaoOS.delete({ where: { id: relacao.id } });
    return { relacaoExcluida: true };
  }

  return { relacaoExcluida: false };
}

// ── Excluir RelacaoOS inteira ─────────────────────────────────────────────────
// Recebe o id da RelacaoOS (não o numeroOS) para identificar unicamente a relação,
// já que OS textuais podem ter múltiplas relações com o mesmo numeroOS.
async function excluirRelacaoOS(relacaoOSId) {
  const relacao = await prisma.relacaoOS.findUnique({
    where:   { id: relacaoOSId },
    include: { movimentacoes: { include: { material: true } } },
  });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível excluir uma OS fechada' };
  }

  // Reverte todas as movimentações
  for (const mov of relacao.movimentacoes) {
    const delta = mov.tipo === 'ENTRADA' ? -Number(mov.quantidade) : Number(mov.quantidade);

    if (mov.material?.especifico) {
      const desc = (mov.descricaoItem ?? '').trim();
      if (desc) {
        const filho   = await prisma.estoqueEspecifico.findUnique({
          where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
        });
        const novaQtd = Math.max(0, Number(filho?.quantidade ?? 0) + delta);
        if (novaQtd === 0) {
          await prisma.estoqueEspecifico.delete({
            where: { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
          }).catch(() => {}); // ignora se não existia
        } else {
          await prisma.estoqueEspecifico.upsert({
            where:  { materialId_descricao: { materialId: mov.materialId, descricao: desc } },
            create: { materialId: mov.materialId, descricao: desc, quantidade: novaQtd },
            update: { quantidade: novaQtd },
          });
        }
      }
    } else {
      await prisma.material.update({
        where: { id: mov.materialId },
        data:  { quantidade: { increment: delta } },
      });
      const mat = await prisma.material.findUnique({ where: { id: mov.materialId } });
      const novoStatus = _calcularStatus(mat.quantidade, mat.estoqueMinimo, mat.ativo);
      await prisma.material.update({ where: { id: mov.materialId }, data: { status: novoStatus } });
    }
  }

  await prisma.movimentacaoEstoque.deleteMany({ where: { relacaoOSId: relacao.id } });
  await prisma.relacaoOS.delete({ where: { id: relacao.id } });
}

// ── Fechar OS ─────────────────────────────────────────────────────────────────
// Recebe o id da RelacaoOS para identificar unicamente a relação.
async function fecharOS(relacaoOSId) {
  const relacao = await prisma.relacaoOS.findUnique({ where: { id: relacaoOSId } });
  if (!relacao) throw { status: 404, message: 'Relação OS não encontrada' };
  if (relacao.status === 'FECHADA') {
    throw { status: 400, message: 'Esta OS já está fechada' };
  }

  return prisma.relacaoOS.update({
    where:   { id: relacaoOSId },
    data:    { status: 'FECHADA' },
    include: _includeMovimentacoes,
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

async function listarTodas(busca) {
  const where = {};
  if (busca) where.numeroOS = { contains: busca, mode: 'insensitive' };

  return prisma.relacaoOS.findMany({
    where,
    include: _includeMovimentacoes,
    orderBy: { atualizadoEm: 'desc' },
  });
}

// ── Atualizar preço de uma movimentação existente ─────────────────────────────
// Permite corrigir o custo de uma movimentação sem precisar removê-la e
// recriá-la. A OS deve estar EM_ANDAMENTO.
// Registra um AuditLogMaterial com acao='CUSTO_MANUAL' para cada campo alterado,
// incluindo quem fez a alteração (usuario.id / usuario.nome) e a data (automática).
async function atualizarPrecoMovimentacao(movimentacaoId, { precoUnitario, precoM2 }, usuario) {
  const mov = await prisma.movimentacaoEstoque.findUnique({
    where:   { id: movimentacaoId },
    include: { relacaoOS: true },
  });
  if (!mov) throw { status: 404, message: 'Movimentação não encontrada' };
  if (mov.relacaoOS?.status === 'FECHADA') {
    throw { status: 400, message: 'Não é possível editar movimentações de uma OS fechada' };
  }

  const data = {};
  if (precoUnitario !== undefined) data.precoUnitario = precoUnitario != null && Number(precoUnitario) > 0 ? Number(precoUnitario) : null;
  if (precoM2       !== undefined) data.precoM2       = precoM2       != null && Number(precoM2)       > 0 ? Number(precoM2)       : null;

  if (Object.keys(data).length === 0) {
    throw { status: 400, message: 'Nenhum campo de preço informado' };
  }

  // ── Monta entradas de audit (captura valorAntes antes de atualizar) ──────────
  const _fmt = (v) => v != null ? `R$ ${Number(v).toFixed(5)}` : null;

  const auditEntries = [];

  if ('precoUnitario' in data) {
    auditEntries.push({
      materialId:  mov.materialId,
      acao:        'CUSTO_MANUAL',
      campo:       'Custo unit. (mov.)',
      valorAntes:  _fmt(mov.precoUnitario),
      valorDepois: _fmt(data.precoUnitario),
      usuarioId:   usuario?.id   ?? null,
      usuarioNome: usuario?.nome ?? null,
    });
  }

  if ('precoM2' in data) {
    auditEntries.push({
      materialId:  mov.materialId,
      acao:        'CUSTO_MANUAL',
      campo:       'Custo m² (mov.)',
      valorAntes:  _fmt(mov.precoM2),
      valorDepois: _fmt(data.precoM2),
      usuarioId:   usuario?.id   ?? null,
      usuarioNome: usuario?.nome ?? null,
    });
  }

  // ── Persiste atualização + audit logs em uma única transação ─────────────────
  const [movimentacaoAtualizada] = await prisma.$transaction([
    prisma.movimentacaoEstoque.update({
      where: { id: movimentacaoId },
      data,
      include: {
        material: {
          select: {
            id: true, nome: true, unidade: true,
            identificador: true, medida: true, espessura: true,
            especifico: true,
          },
        },
      },
    }),
    ...auditEntries.map((entry) => prisma.auditLogMaterial.create({ data: entry })),
  ]);

  return movimentacaoAtualizada;
}

// ── Renomear OS ───────────────────────────────────────────────────────────────
async function renomearOS(id, novoNumeroOS) {
  const novoNome = (novoNumeroOS ?? '').trim().toUpperCase();
  if (!novoNome) throw { status: 400, message: 'Nome da OS não pode ser vazio' };

  const relacao = await prisma.relacaoOS.findUnique({ where: { id } });
  if (!relacao) throw { status: 404, message: 'OS não encontrada' };

  // Garante que não existe outra RelacaoOS com o mesmo nome
  const conflito = await prisma.relacaoOS.findUnique({ where: { numeroOS: novoNome } });
  if (conflito && conflito.id !== id) {
    throw { status: 409, message: `Já existe uma OS com o nome "${novoNome}"` };
  }

  // Atualiza o nome na RelacaoOS
  const atualizada = await prisma.relacaoOS.update({
    where: { id },
    data:  { numeroOS: novoNome },
    include: _includeMovimentacoes,
  });

  // Sincroniza o campo numeroOS em todas as movimentações vinculadas
  await prisma.movimentacaoEstoque.updateMany({
    where: { relacaoOSId: id },
    data:  { numeroOS: novoNome },
  });

  return atualizada;
}

module.exports = {
  listarEmAndamento,
  buscarPorNumeroOS,
  registrarMovimentacao,
  removerMovimentacao,
  excluirRelacaoOS,
  fecharOS,
  listarTodas,
  renomearOS,
  atualizarPrecoMovimentacao,
};