const orcamentoPdfService = require('../services/orcamento_pdf.service');

/**
 * POST /api/orcamentos/pdf
 * Recebe os dados do orçamento (tab atual do cliente) e devolve o PDF como download.
 *
 * Body esperado:
 * {
 *   titulo: string,
 *   itens: [
 *     {
 *       materialId:           number,
 *       materialNome:         string,
 *       materialUnidade:      string | null,
 *       quantidade:           number,
 *       modoOrcamento:        'unitario' | 'metroQuadrado' | null,
 *       fornecedorSelecionado: number | null,
 *       precos: {
 *         [fornecedorId]: { fornecedorNome: string, preco: number|null, precoM2: number|null }
 *       }
 *     }
 *   ]
 * }
 */
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