const pdfService = require('../services/relatorioOS.pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const { numeroOS } = req.params;

    const buffer = await pdfService.gerarPdfOS(numeroOS);

    // Número limpo para o nome do arquivo (remove sufixo interno #OC…)
    const numeroLimpo = numeroOS.includes('#OC')
      ? numeroOS.substring(0, numeroOS.indexOf('#OC'))
      : numeroOS;
    const filename = `relatorio_os_${numeroLimpo.replace(/\W/g, '_')}.pdf`;

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