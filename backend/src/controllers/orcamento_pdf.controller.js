const orcamentoPdfService = require('../services/orcamento_pdf.service');

const gerarPdf = async (req, res, next) => {
  try {
    const dados = req.body;

    if (!dados || !Array.isArray(dados.itens)) {
      return res.status(400).json({ message: 'Dados inválidos: campo "itens" obrigatório.' });
    }

    // O front já bloqueia isso antes de chamar (ver
    // OrcamentoEditorPage._exportarPdf), mas essa é a validação que
    // realmente importa: sem ela, um item de material genérico sem
    // descrição vai para o PDF só com o nome do pai (ex.: "TINTA"),
    // indistinguível de outras variantes do mesmo material genérico no
    // comparativo. `ehGenerico` aqui reflete o item como o Flutter o
    // monta (ItemOrcamentoData.toJson) — true tanto pra um item de
    // rascunho ainda apontando pro pai genérico quanto pra um item já
    // resolvido para um Material filho, então a checagem de descrição
    // funciona nos dois casos.
    const genericosSemDescricao = dados.itens.filter(
      (item) => item?.ehGenerico && !String(item?.descricaoItem ?? item?.descricao ?? '').trim()
    );
    if (genericosSemDescricao.length > 0) {
      const nomes = [...new Set(genericosSemDescricao.map((i) => i.materialNome).filter(Boolean))].join(', ');
      return res.status(400).json({
        message: nomes
          ? `Preencha a descrição dos materiais genéricos antes de gerar o PDF: ${nomes}.`
          : 'Preencha a descrição de todos os materiais genéricos antes de gerar o PDF.',
      });
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