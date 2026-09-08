// controllers/contaPagar.controller.js
const prisma = require('../utils/prisma');
const { extrairDadosNFe, NotaFiscalXmlError } = require('../services/notaFiscalXml.service');

function paraDecimalOuNull(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

// GET /api/contas-pagar?status=PENDENTE&empresaId=1&de=2026-08-01&ate=2026-08-31
exports.listar = async (req, res, next) => {
  try {
    const { status, empresaId, de, ate, q } = req.query;

    const where = {};
    if (status) where.status = status;
    if (empresaId) where.empresaId = Number(empresaId);
    if (de || ate) {
      where.dataVencimento = {};
      if (de) where.dataVencimento.gte = new Date(de);
      if (ate) where.dataVencimento.lte = new Date(ate);
    }
    if (q) {
      where.OR = [
        { descricao: { contains: q, mode: 'insensitive' } },
        { numeroDocumento: { contains: q, mode: 'insensitive' } },
      ];
    }

    const contas = await prisma.contaPagar.findMany({
      where,
      include: {
        empresa: true,
        notaFiscal: true,
      },
      orderBy: [{ status: 'asc' }, { dataVencimento: 'asc' }],
    });

    // Marca como VENCIDO em tempo de leitura quem passou da data e ainda está PENDENTE
    // (sem sujar o banco a cada request; um job/cron pode persistir isso periodicamente).
    const hoje = new Date();
    hoje.setHours(0, 0, 0, 0);
    const contasComStatusCalculado = contas.map((c) => {
      if (c.status === 'PENDENTE' && new Date(c.dataVencimento) < hoje) {
        return { ...c, statusExibicao: 'VENCIDO' };
      }
      return { ...c, statusExibicao: c.status };
    });

    res.json(contasComStatusCalculado);
  } catch (err) {
    next(err);
  }
};

// GET /api/contas-pagar/:id
exports.buscarPorId = async (req, res, next) => {
  try {
    const conta = await prisma.contaPagar.findUnique({
      where: { id: Number(req.params.id) },
      include: { empresa: true, notaFiscal: true },
    });
    if (!conta) return res.status(404).json({ error: 'Conta a pagar não encontrada.' });
    res.json(conta);
  } catch (err) {
    next(err);
  }
};

// POST /api/contas-pagar  (cadastro manual, sem XML)
exports.criar = async (req, res, next) => {
  try {
    const {
      descricao, numeroDocumento, valor, dataEmissao, dataVencimento,
      empresaId, emitenteNome, emitenteCnpj, formaPagamento, categoria, observacao,
    } = req.body;

    if (!descricao || !valor || !dataVencimento) {
      return res.status(400).json({ error: 'descricao, valor e dataVencimento são obrigatórios.' });
    }

    const conta = await prisma.contaPagar.create({
      data: {
        descricao,
        numeroDocumento: numeroDocumento || null,
        valor: paraDecimalOuNull(valor),
        dataEmissao: dataEmissao ? new Date(dataEmissao) : null,
        dataVencimento: new Date(dataVencimento),
        empresaId: empresaId ? Number(empresaId) : null,
        emitenteNome: emitenteNome || null,
        emitenteCnpj: emitenteCnpj || null,
        formaPagamento: formaPagamento || null,
        categoria: categoria || null,
        observacao: observacao || null,
        criadoPorId: req.usuario?.id ?? null,
        criadoPorNome: req.usuario?.nome ?? null,
      },
    });

    res.status(201).json(conta);
  } catch (err) {
    next(err);
  }
};

// POST /api/contas-pagar/importar-xml  (multipart/form-data, campo "arquivo")
// Faz o parse do XML da NF-e, cria/reaproveita o registro de NotaFiscal e
// devolve os dados prontos para o usuário revisar/completar (vencimento,
// forma de pagamento, categoria) antes de confirmar a criação da Conta a Pagar.
exports.importarXml = async (req, res, next) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Nenhum arquivo XML enviado.' });
    }

    const xmlString = req.file.buffer.toString('utf8');
    const dados = extrairDadosNFe(xmlString);

    const notaExistente = await prisma.notaFiscal.findUnique({
      where: { chaveAcesso: dados.chaveAcesso },
      include: { contaPagar: true },
    });

    if (notaExistente?.contaPagar) {
      return res.status(409).json({
        error: 'Esta nota fiscal já possui uma Conta a Pagar cadastrada.',
        contaPagarId: notaExistente.contaPagar.id,
      });
    }

    const notaFiscal = notaExistente
      ? notaExistente
      : await prisma.notaFiscal.create({
          data: {
            chaveAcesso: dados.chaveAcesso,
            numero: dados.numero,
            serie: dados.serie,
            dataEmissao: dados.dataEmissao,
            valorTotal: dados.valorTotal,
            emitenteCnpj: dados.emitenteCnpj,
            emitenteNome: dados.emitenteNome,
            destinatarioCnpj: dados.destinatarioCnpj,
            destinatarioNome: dados.destinatarioNome,
            xmlOriginal: xmlString,
            origem: 'XML_MANUAL',
          },
        });

    res.json({
      notaFiscal,
      // Sugestão de vencimento padrão: 30 dias após emissão (o usuário ajusta na tela)
      vencimentoSugerido: dados.dataEmissao
        ? new Date(dados.dataEmissao.getTime() + 30 * 24 * 60 * 60 * 1000)
        : null,
    });
  } catch (err) {
    if (err instanceof NotaFiscalXmlError) {
      return res.status(err.status).json({ error: err.message });
    }
    next(err);
  }
};

// POST /api/contas-pagar/confirmar-nota/:notaFiscalId
// Depois que o usuário revisou os dados extraídos do XML (importar-xml),
// confirma a criação da Conta a Pagar vinculada a essa nota.
exports.confirmarContaDeNota = async (req, res, next) => {
  try {
    const notaFiscalId = Number(req.params.notaFiscalId);
    const {
      dataVencimento, valor, empresaId,
      formaPagamento, categoria, observacao, descricao,
    } = req.body;

    if (!dataVencimento) {
      return res.status(400).json({ error: 'dataVencimento é obrigatória.' });
    }

    const notaFiscal = await prisma.notaFiscal.findUnique({ where: { id: notaFiscalId } });
    if (!notaFiscal) return res.status(404).json({ error: 'Nota fiscal não encontrada.' });

    const conta = await prisma.contaPagar.create({
      data: {
        notaFiscalId,
        descricao: descricao || `NF-e ${notaFiscal.numero ?? ''} — ${notaFiscal.emitenteNome ?? 'Emitente'}`,
        numeroDocumento: notaFiscal.numero,
        emitenteNome: notaFiscal.emitenteNome,
        emitenteCnpj: notaFiscal.emitenteCnpj,
        valor: paraDecimalOuNull(valor) ?? notaFiscal.valorTotal,
        dataEmissao: notaFiscal.dataEmissao,
        dataVencimento: new Date(dataVencimento),
        empresaId: empresaId ? Number(empresaId) : null,
        formaPagamento: formaPagamento || null,
        categoria: categoria || null,
        observacao: observacao || null,
        criadoPorId: req.usuario?.id ?? null,
        criadoPorNome: req.usuario?.nome ?? null,
      },
      include: { notaFiscal: true, empresa: true },
    });

    res.status(201).json(conta);
  } catch (err) {
    next(err);
  }
};

// PATCH /api/contas-pagar/:id
exports.atualizar = async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const {
      descricao, numeroDocumento, valor, dataVencimento,
      formaPagamento, categoria, observacao, empresaId,
    } = req.body;

    const conta = await prisma.contaPagar.update({
      where: { id },
      data: {
        ...(descricao !== undefined && { descricao }),
        ...(numeroDocumento !== undefined && { numeroDocumento }),
        ...(valor !== undefined && { valor: paraDecimalOuNull(valor) }),
        ...(dataVencimento !== undefined && { dataVencimento: new Date(dataVencimento) }),
        ...(formaPagamento !== undefined && { formaPagamento }),
        ...(categoria !== undefined && { categoria }),
        ...(observacao !== undefined && { observacao }),
        ...(empresaId !== undefined && { empresaId: empresaId ? Number(empresaId) : null }),
      },
    });

    res.json(conta);
  } catch (err) {
    next(err);
  }
};

// POST /api/contas-pagar/:id/pagar
exports.marcarComoPaga = async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const { dataPagamento, formaPagamento } = req.body;

    const conta = await prisma.contaPagar.update({
      where: { id },
      data: {
        status: 'PAGO',
        dataPagamento: dataPagamento ? new Date(dataPagamento) : new Date(),
        formaPagamento: formaPagamento || undefined,
        pagoPorId: req.usuario?.id ?? null,
        pagoPorNome: req.usuario?.nome ?? null,
      },
    });

    res.json(conta);
  } catch (err) {
    next(err);
  }
};

// POST /api/contas-pagar/:id/status
// Permite alterar o status para qualquer valor válido (PENDENTE, VENCIDO, PAGO, CANCELADO).
// Ao ir para PAGO, registra dataPagamento/quem pagou; ao sair de PAGO, limpa esses campos.
exports.atualizarStatus = async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const { status } = req.body;
    const statusValidos = ['PENDENTE', 'VENCIDO', 'PAGO', 'CANCELADO'];

    if (!statusValidos.includes(status)) {
      return res.status(400).json({
        error: `Status inválido. Use um dos seguintes: ${statusValidos.join(', ')}.`,
      });
    }

    const data = { status };
    if (status === 'PAGO') {
      data.dataPagamento = new Date();
      data.pagoPorId = req.usuario?.id ?? null;
      data.pagoPorNome = req.usuario?.nome ?? null;
    } else {
      data.dataPagamento = null;
      data.pagoPorId = null;
      data.pagoPorNome = null;
    }

    const conta = await prisma.contaPagar.update({ where: { id }, data });
    res.json(conta);
  } catch (err) {
    next(err);
  }
};

// POST /api/contas-pagar/:id/cancelar
exports.cancelar = async (req, res, next) => {
  try {
    const conta = await prisma.contaPagar.update({
      where: { id: Number(req.params.id) },
      data: { status: 'CANCELADO' },
    });
    res.json(conta);
  } catch (err) {
    next(err);
  }
};

// DELETE /api/contas-pagar/:id
exports.excluir = async (req, res, next) => {
  try {
    await prisma.contaPagar.delete({ where: { id: Number(req.params.id) } });
    res.status(204).send();
  } catch (err) {
    next(err);
  }
};

// GET /api/contas-pagar/resumo  (cards de totais para o topo da tela)
exports.resumo = async (req, res, next) => {
  try {
    const hoje = new Date();
    hoje.setHours(0, 0, 0, 0);

    const [pendentes, vencidas, pagasNoMes] = await Promise.all([
      prisma.contaPagar.aggregate({
        where: { status: 'PENDENTE', dataVencimento: { gte: hoje } },
        _sum: { valor: true },
        _count: true,
      }),
      prisma.contaPagar.aggregate({
        where: { status: 'PENDENTE', dataVencimento: { lt: hoje } },
        _sum: { valor: true },
        _count: true,
      }),
      prisma.contaPagar.aggregate({
        where: {
          status: 'PAGO',
          dataPagamento: { gte: new Date(hoje.getFullYear(), hoje.getMonth(), 1) },
        },
        _sum: { valor: true },
        _count: true,
      }),
    ]);

    res.json({
      pendentes: { total: pendentes._sum.valor ?? 0, quantidade: pendentes._count },
      vencidas: { total: vencidas._sum.valor ?? 0, quantidade: vencidas._count },
      pagasNoMes: { total: pagasNoMes._sum.valor ?? 0, quantidade: pagasNoMes._count },
    });
  } catch (err) {
    next(err);
  }
};