const orcamentoPdfService = require('../services/orcamento_pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const dados = req.body;

    if (!dados || !Array.isArray(dados.itens)) {
      return res.status(400).json({ message: 'Dados inválidos: campo "itens" obrigatório.' });
    }

    const pdfBuffer = await orcamentoPdfService.gerarPdfDeItens(dados);

    const hoje = new Date().toLocaleDateString('pt-BR').replace(/\//g, '-');

    res.set({
      'Content-Type':        'application/pdf',
      'Content-Disposition': `attachment; filename="orcamento(${hoje}).pdf"`,
      'Content-Length':      pdfBuffer.length,
    });

    res.send(pdfBuffer);
  } catch (e) {
    next(e);
  }
};

module.exports = { gerarPdf };