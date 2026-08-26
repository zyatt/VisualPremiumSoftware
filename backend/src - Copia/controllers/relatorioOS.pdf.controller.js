const relatorioOSPdfSvc = require('../services/relatorioOS_pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const { numeroOS } = req.params;

    const pdfBuffer = await relatorioOSPdfSvc.gerarPdfOS(numeroOS);

    const hoje = new Date().toLocaleDateString('pt-BR').replace(/\//g, '-');

    res.set({
      'Content-Type':        'application/pdf',
      'Content-Disposition': `inline; filename="OS-${numeroOS}(${hoje}).pdf"`,
      'Content-Length':      pdfBuffer.length,
    });

    res.send(pdfBuffer);
  } catch (e) {
    next(e);
  }
};

module.exports = { gerarPdf };