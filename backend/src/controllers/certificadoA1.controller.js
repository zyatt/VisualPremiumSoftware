// controllers/certificadoA1.controller.js
const prisma = require('../utils/prisma');
const certServico = require('../services/certificadoA1.service');

// GET /api/certificados-a1
exports.listar = async (req, res, next) => {
  try {
    const certificados = await prisma.certificadoDigital.findMany({
      include: { empresa: true },
      orderBy: { criadoEm: 'desc' },
    });
    // nunca devolve a senha, nem o path físico do arquivo
    res.json(certificados.map(({ senhaCriptografada, arquivoPath, ...c }) => c));
  } catch (err) {
    next(err);
  }
};

// POST /api/certificados-a1  (multipart: arquivo=.pfx/.p12, campos empresaId, senha, validade)
exports.cadastrar = async (req, res, next) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Envie o arquivo do certificado (.pfx ou .p12).' });
    }
    const { empresaId, senha, validade } = req.body;
    if (!empresaId || !senha) {
      return res.status(400).json({ error: 'empresaId e senha são obrigatórios.' });
    }

    const arquivoPath = certServico.salvarArquivoCertificado(
      Number(empresaId),
      req.file.buffer,
      req.file.originalname
    );
    const senhaCriptografada = certServico.criptografarSenha(senha);

    const certificado = await prisma.certificadoDigital.upsert({
      where: { empresaId: Number(empresaId) },
      update: {
        arquivoNome: req.file.originalname,
        arquivoPath,
        senhaCriptografada,
        validade: validade ? new Date(validade) : null,
        ativo: false, // fica desligado até você confirmar/ativar manualmente
        ultimoErro: null,
      },
      create: {
        empresaId: Number(empresaId),
        arquivoNome: req.file.originalname,
        arquivoPath,
        senhaCriptografada,
        validade: validade ? new Date(validade) : null,
        ativo: false,
      },
    });

    const { senhaCriptografada: _omit, ...resposta } = certificado;
    res.status(201).json(resposta);
  } catch (err) {
    next(err);
  }
};

// POST /api/certificados-a1/:id/ativar — liga a busca automática (quando implementada)
exports.ativar = async (req, res, next) => {
  try {
    const certificado = await prisma.certificadoDigital.update({
      where: { id: Number(req.params.id) },
      data: { ativo: true },
    });
    const { senhaCriptografada, ...resposta } = certificado;
    res.json(resposta);
  } catch (err) {
    next(err);
  }
};

// POST /api/certificados-a1/:id/buscar-notas — dispara a busca manual (placeholder)
exports.buscarNotas = async (req, res, next) => {
  try {
    const certificado = await prisma.certificadoDigital.findUnique({
      where: { id: Number(req.params.id) },
    });
    if (!certificado) return res.status(404).json({ error: 'Certificado não encontrado.' });

    await certServico.buscarNotasNaSefaz(certificado);
    res.json({ ok: true });
  } catch (err) {
    // Erro esperado enquanto a integração SEFAZ não está implementada
    res.status(501).json({ error: err.message });
  }
};