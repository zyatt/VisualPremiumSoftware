const prisma = require('../utils/prisma');
const materialSvc = require('./material.service');

const _includeSolicitacao = {
  material: {
    select: {
      id: true, nome: true, unidade: true, quantidade: true,
      estoqueMinimo: true, identificador: true, medida: true,
      espessura: true, categoria: true, status: true,
      ultimoValorPago: true, ultimoValorPagoM2: true, largura: true, comprimento: true,
    },
  },
  baixas: { orderBy: { criadoEm: 'asc' } },
};

function _formatarMedidaRetalho(areaM2) {
  return `${Number(areaM2).toFixed(2)}m²`;
}

function _calcularStatus(quantidade, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const q   = Number(quantidade);
  const min = Number(estoqueMinimo);
  if (q > min) return 'OK';
  if (q === min) return 'LIMITE';
  return 'CRITICO';
}

function _statusComReserva(estoqueAtual, emUso, estoqueMinimo, ativo) {
  if (!ativo) return 'INATIVO';
  const disponivel = Number(estoqueAtual) + Number(emUso);
  const min        = Number(estoqueMinimo);
  if (disponivel > min)  return 'OK';
  if (disponivel === min) return 'LIMITE';
  return 'CRITICO';
}

async function _emUsoMaterial(materialId) {
  const ativas = await prisma.solicitacaoProducao.findMany({
    where: { materialId, status: { in: ['ABERTA', 'EM_USO'] } },
    select: { quantidadeReservada: true, quantidadeUsada: true },
  });
  return ativas.reduce((acc, s) => {
    const restante = Math.max(0, Number(s.quantidadeReservada) - Number(s.quantidadeUsada));
    return acc + restante;
  }, 0);
}

async function listarMateriais({ busca, categoria, status, id, identificador, medida, espessura } = {}) {
  const where = { ativo: true };

  if (id) {
    const idNum = parseInt(id, 10);
    if (!isNaN(idNum)) where.id = idNum;
  }
  if (busca)         where.nome           = { contains: busca,         mode: 'insensitive' };
  if (categoria)     where.categoria      = { equals:   categoria,     mode: 'insensitive' };
  if (identificador) where.identificador  = { contains: identificador, mode: 'insensitive' };
  if (medida)        where.medida         = { contains: medida,        mode: 'insensitive' };
  if (espessura)     where.espessura      = { contains: espessura,     mode: 'insensitive' };
  if (status)        where.status         = status;

  const materiais = await prisma.material.findMany({
    where,
    orderBy: [{ categoria: 'asc' }, { nome: 'asc' }],
  });

  const resultado = await Promise.all(
    materiais.map(async (m) => {
      const emUso      = await _emUsoMaterial(m.id);
      const statusReal = _statusComReserva(m.quantidade, emUso, m.estoqueMinimo, m.ativo);
      return { ...m, emUso, statusReal };
    })
  );

  return resultado;
}

async function criarSolicitacao({ materialId, descricaoItem, quantidadeReservada, numeroOS, usuarioId, usuarioNome, larguraUsada, comprimentoUsado }) {
  const material = await prisma.material.findUnique({ where: { id: materialId } });
  if (!material || !material.ativo) throw { status: 404, message: 'Material não encontrado ou inativo' };

  const usuario = await prisma.usuario.findUnique({ where: { id: usuarioId }, select: { nome: true } });
  const nomeReal = usuario?.nome ?? usuarioNome;

  const numeroOSNorm = (numeroOS ?? '').trim().toUpperCase();

  const saldo = Number(material.quantidade);
  if (saldo < Number(quantidadeReservada)) {
    throw {
      status: 400,
      message: `Estoque insuficiente: disponível ${saldo} ${material.unidade ?? ''}`.trim(),
    };
  }
  await prisma.material.update({
    where: { id: materialId },
    data:  { quantidade: { decrement: Number(quantidadeReservada) } },
  });

  const qtd = Number(quantidadeReservada);

  const matAtualizado = await prisma.material.findUnique({ where: { id: materialId } });
  const emUso         = await _emUsoMaterial(materialId);
  const novoStatus    = _statusComReserva(matAtualizado.quantidade, emUso, matAtualizado.estoqueMinimo, matAtualizado.ativo);
  await prisma.material.update({ where: { id: materialId }, data: { status: novoStatus } });
  materialSvc.notificarSeCritico(material.status, { ...matAtualizado, status: novoStatus });

  const solicitacao = await prisma.solicitacaoProducao.create({
    data: {
      numeroOS: numeroOSNorm,
      materialId,
      descricaoItem: descricaoItem ?? null,
      quantidadeReservada: qtd,
      quantidadeUsada: qtd,
      status: 'FINALIZADA',
      finalizadoEm: new Date(),
      usuarioId,
      usuarioNome: nomeReal,
    },
    include: _includeSolicitacao,
  });

  await _registrarSaidaControleEstoque(solicitacao, { larguraUsada, comprimentoUsado });

  return solicitacao;
}

async function registrarBaixa({ solicitacaoId, quantidade, observacao }) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id: solicitacaoId },
    include: { material: true },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  if (sol.status === 'FINALIZADA') throw { status: 400, message: 'Solicitação já finalizada' };

  const restante = Number(sol.quantidadeReservada) - Number(sol.quantidadeUsada);
  if (Number(quantidade) > restante) {
    throw {
      status: 400,
      message: `Baixa (${quantidade}) excede o saldo em uso (${restante.toFixed(3)})`,
    };
  }

  const novaUsada = Number(sol.quantidadeUsada) + Number(quantidade);

  await prisma.baixaProducao.create({
    data: { solicitacaoId, quantidade: Number(quantidade), observacao: observacao ?? null },
  });

  const atualizada = await prisma.solicitacaoProducao.update({
    where: { id: solicitacaoId },
    data: {
      quantidadeUsada: novaUsada,
      status: 'EM_USO',
    },
    include: _includeSolicitacao,
  });

  const mat    = await prisma.material.findUnique({ where: { id: sol.materialId } });
  const emUso  = await _emUsoMaterial(sol.materialId);
  const novoSt = _statusComReserva(mat.quantidade, emUso, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: sol.materialId }, data: { status: novoSt } });
  materialSvc.notificarSeCritico(sol.material.status, { ...mat, status: novoSt });
  return atualizada;
}

async function finalizarSolicitacao({ solicitacaoId }) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id: solicitacaoId },
    include: { material: true, baixas: true },
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  if (sol.status === 'FINALIZADA') throw { status: 400, message: 'Solicitação já finalizada' };

  const sobra = Math.max(0, Number(sol.quantidadeReservada) - Number(sol.quantidadeUsada));

  if (sobra > 0) {
    await prisma.material.update({
      where: { id: sol.materialId },
      data:  { quantidade: { increment: sobra } },
    });
  }

  const finalizada = await prisma.solicitacaoProducao.update({
    where: { id: solicitacaoId },
    data:  { status: 'FINALIZADA', finalizadoEm: new Date() },
    include: _includeSolicitacao,
  });

  if (Number(sol.quantidadeUsada) > 0) {
    await _registrarSaidaControleEstoque(finalizada);
  }

  const mat    = await prisma.material.findUnique({ where: { id: sol.materialId } });
  const emUso  = await _emUsoMaterial(sol.materialId);
  const novoSt = _statusComReserva(mat.quantidade, emUso, mat.estoqueMinimo, mat.ativo);
  await prisma.material.update({ where: { id: sol.materialId }, data: { status: novoSt } });
  materialSvc.notificarSeCritico(sol.material.status, { ...mat, status: novoSt });

  return finalizada;
}

async function excluirHistorico(solicitacaoId) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where: { id: solicitacaoId },
  });
  if (!sol) throw { status: 404, message: 'Registro não encontrado' };
  if (sol.status !== 'FINALIZADA') {
    throw { status: 400, message: 'Somente solicitações finalizadas podem ser excluídas do histórico' };
  }

  await prisma.solicitacaoProducao.delete({ where: { id: solicitacaoId } });
}

async function _registrarSaidaControleEstoque(sol, { larguraUsada, comprimentoUsado } = {}) {
  const qtdUsada = Number(sol.quantidadeUsada);
  if (qtdUsada <= 0) return;

  const observacao = `Saída via produção – ${sol.usuarioNome}`;
  const numeroOS   = sol.numeroOS;

  const material = sol.material ?? await prisma.material.findUnique({
    where: { id: sol.materialId },
    select: { ultimoValorPago: true, ultimoValorPagoM2: true, largura: true, comprimento: true, unidade: true },
  });
  const precoUnitario = material?.ultimoValorPago   ? Number(material.ultimoValorPago)   : null;
  let precoM2       = material?.ultimoValorPagoM2 ? Number(material.ultimoValorPagoM2) : null;

  let precoUnitarioFinal = precoUnitario;
  let precoM2Final       = precoM2;

  const _unidadeMat = (material?.unidade ?? '').toLowerCase().trim();
  const _eMetroLinear = ['m', 'ml', 'm/l', 'metro', 'metros', 'metro linear', 'metros lineares'].includes(_unidadeMat);

  if (_eMetroLinear) {
    precoM2Final = null;
  }

  if (
    larguraUsada != null && comprimentoUsado != null &&
    !_eMetroLinear &&
    material?.largura != null && material?.comprimento != null
  ) {
    const larg      = Number(larguraUsada);
    const comp      = Number(comprimentoUsado);
    const largTotal = Number(material.largura);
    const compTotal = Number(material.comprimento);

    if (larg > 0 && comp > 0 && largTotal > 0 && compTotal > 0) {
      const areaUsada = larg * comp;
      const areaTotal = largTotal * compTotal;
      const custoM2 = precoM2Final != null
        ? Number(precoM2Final)
        : (precoUnitarioFinal != null && areaTotal > 0
            ? Number(precoUnitarioFinal) / areaTotal
            : null);
      if (custoM2 != null) {
        precoM2Final = Math.round(custoM2 * areaUsada * 100000) / 100000;
      }
    }
  }

  const osEhNumerica = /^\d+$/.test(numeroOS);

  const _d   = new Date();
  const hoje = `${String(_d.getDate()).padStart(2,'0')}-${String(_d.getMonth()+1).padStart(2,'0')}-${_d.getFullYear()}`;

  let relacao;
  if (osEhNumerica) {
    relacao = await prisma.relacaoOS.upsert({
      where:  { numeroOS },
      create: { numeroOS, status: 'EM_ANDAMENTO' },
      update: {},
    });
  } else {
    const relacaoAberta = await prisma.relacaoOS.findFirst({
      where: {
        status: 'EM_ANDAMENTO',
        OR: [
          { numeroOS: numeroOS },
          { numeroOS: { startsWith: `${numeroOS}-${hoje}` } },
        ],
      },
      orderBy: { criadoEm: 'asc' },
    });

    if (relacaoAberta) {
      relacao = relacaoAberta;
    } else {
      let candidato = `${numeroOS}-${hoje}`;
      let sufixoSeq = 1;

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

  await prisma.movimentacaoEstoque.create({
    data: {
      materialId:    sol.materialId,
      tipo:          'SAIDA',
      quantidade:    qtdUsada,
      numeroOS,
      relacaoOSId:   relacao.id,
      descricaoItem: sol.descricaoItem ?? null,
      observacao,
      precoUnitario: precoUnitarioFinal ?? undefined,
      precoM2:       precoM2Final       ?? undefined,
      larguraUsada: (larguraUsada != null ? Number(larguraUsada) : null),
      comprimentoUsado: (comprimentoUsado != null ? Number(comprimentoUsado) : null),
      origemProducao: 'SOLICITACAO_ESTOQUE_NORMAL',
    },
  });

  if (
    !sol.descricaoItem &&
    larguraUsada != null && comprimentoUsado != null &&
    material?.largura != null && material?.comprimento != null
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
        const materialData = await prisma.material.findUnique({
          where: { id: sol.materialId },
          select: { nome: true, espessura: true, categoria: true, medida: true },
        });

        const medidaRetalho = _formatarMedidaRetalho(areaRetalho);

        let retalhoMat = await prisma.material.findFirst({
          where: {
            nome:          { equals: materialData.nome, mode: 'insensitive' },
            identificador: { equals: 'RETALHO',    mode: 'insensitive' },
            medida:        { equals: medidaRetalho, mode: 'insensitive' },
            espessura:     materialData.espessura
              ? { equals: materialData.espessura, mode: 'insensitive' }
              : null,
          },
        });

        const custoM2Retalho = (() => {
          if (precoM2Final != null && precoM2Final > 0) {
            const areaUsada = larg * comp;
            if (areaUsada > 0) return precoM2Final / areaUsada;
          }
          const pu = precoUnitarioFinal != null ? Number(precoUnitarioFinal) : null;
          const areaT = largTotal * compTotal;
          if (pu != null && pu > 0 && areaT > 0) return pu / areaT;
          return material.ultimoValorPagoM2 != null ? Number(material.ultimoValorPagoM2) : null;
        })();

        if (!retalhoMat) {
          try {
            retalhoMat = await prisma.material.create({
              data: {
                nome:              materialData.nome,
                unidade:           'M2',
                categoria:         materialData.categoria   ?? null,
                medida:            medidaRetalho,
                espessura:         materialData.espessura   ?? null,
                identificador:     'RETALHO',
                quantidade:        areaRetalho,
                estoqueMinimo:     0,
                status:            _calcularStatus(areaRetalho, 0, true),
                estoqueConfirmado: false,
                ativo:             true,
                ultimoValorPago:   null,
                ultimoValorPagoM2: custoM2Retalho,
              },
            });
          } catch (err) {
            if (err?.code === 'P2002') {
              retalhoMat = await prisma.material.findFirst({
                where: {
                  nome:      { equals: materialData.nome, mode: 'insensitive' },
                  medida:    { equals: medidaRetalho, mode: 'insensitive' },
                  espessura: materialData.espessura
                    ? { equals: materialData.espessura, mode: 'insensitive' }
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
          const novaQtd = Number(retalhoMat.quantidade) + areaRetalho;
          await prisma.material.update({
            where: { id: retalhoMat.id },
            data: {
              quantidade:        novaQtd,
              status:            _calcularStatus(novaQtd, Number(retalhoMat.estoqueMinimo), retalhoMat.ativo),
              ultimoValorPago:   null,
              ...(custoM2Retalho != null ? { ultimoValorPagoM2: custoM2Retalho } : {}),
            },
          });
        }
      }
    }
  }
}

async function listarSolicitacoes({ usuarioId, status, busca } = {}) {
  const where = {};
  if (usuarioId) where.usuarioId = usuarioId;
  if (status)    where.status    = Array.isArray(status) ? { in: status } : status;
  if (busca)     where.OR = [
    { numeroOS:    { contains: busca, mode: 'insensitive' } },
    { usuarioNome: { contains: busca, mode: 'insensitive' } },
  ];

  return prisma.solicitacaoProducao.findMany({
    where,
    include: _includeSolicitacao,
    orderBy: { atualizadoEm: 'desc' },
  });
}

async function buscarSolicitacao(id) {
  const sol = await prisma.solicitacaoProducao.findUnique({
    where:   { id },
    include: _includeSolicitacao,
  });
  if (!sol) throw { status: 404, message: 'Solicitação não encontrada' };
  return sol;
}

async function listarCategorias() {
  const cats = await prisma.material.findMany({
    where:    { ativo: true, categoria: { not: null } },
    select:   { categoria: true },
    distinct: ['categoria'],
    orderBy:  { categoria: 'asc' },
  });
  return cats.map((c) => c.categoria).filter(Boolean);
}

module.exports = {
  listarMateriais,
  criarSolicitacao,
  registrarBaixa,
  finalizarSolicitacao,
  excluirHistorico,
  listarSolicitacoes,
  buscarSolicitacao,
  listarCategorias,
};