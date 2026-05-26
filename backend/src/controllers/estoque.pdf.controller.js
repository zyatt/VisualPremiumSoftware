const pdfService = require('../services/estoque.pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const categoria = req.query.categoria || 'TODAS';
    const status = req.query.status || 'TODOS';

    const buffer = await pdfService.gerarPdf(categoria, status);

    const nomeCategoria = categoria.toUpperCase().replace(/\s+/g, '_');
    const nomeStatus = status.toUpperCase().replace(/\s+/g, '_');

    const filename = `estoque_${nomeCategoria}_${nomeStatus}.pdf`;

    res.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': `inline; filename="${filename}"`,
      'Content-Length': buffer.length,
    });

    res.end(buffer);
  } catch (e) {
    next(e);
  }
};

module.exports = { gerarPdf };