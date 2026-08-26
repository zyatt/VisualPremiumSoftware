const pdfService = require('../services/ordemCompra.pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const buffer = await pdfService.gerarPdf(+req.params.id);
    res.set({
      'Content-Type':        'application/pdf',
      'Content-Disposition': `inline; filename="OC-${req.params.id}.pdf"`,
      'Content-Length':      buffer.length,
    });
    res.end(buffer);
  } catch (e) {
    next(e);
  }
};

module.exports = { gerarPdf };