const pdfService = require('../services/estoque.pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    // categoria pode vir como query param: ?categoria=LONA ou TODAS / vazio
    const categoria = req.query.categoria || 'TODAS';

    const buffer = await pdfService.gerarPdf(categoria);

    // Nome do arquivo: estoque_TODAS.pdf  ou  estoque_LONA.pdf
    const nomeCategoria = categoria.toUpperCase().replace(/\s+/g, '_');
    const filename = `estoque_${nomeCategoria}.pdf`;

    res.set({
      'Content-Type':        'application/pdf',
      'Content-Disposition': `inline; filename="${filename}"`,
      'Content-Length':      buffer.length,
    });
    res.end(buffer);
  } catch (e) {
    next(e);
  }
};

module.exports = { gerarPdf };