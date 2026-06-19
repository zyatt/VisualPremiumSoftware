const PDFDocument = require('pdfkit');
const path        = require('path');
const svc         = require('./relatorioOS.service');

// ── Helpers de formatação ─────────────────────────────────────────────────────

/**
 * Formata um valor monetário com até 6 casas decimais,
 * removendo zeros à direita (mínimo 2 casas).
 * Ex.: 1.5 → "R$ 1,50";  0.000125 → "R$ 0,000125";  1.23456 → "R$ 1,23456"
 */
function formatCurrency(value) {
  const n = Number(value ?? 0);
  // Renderiza com 6 casas e remove zeros à direita, mantendo mínimo 2
  const s6 = n.toFixed(6);
  const trimmed = s6.replace(/0+$/, '');
  const [intPart, decPart = ''] = trimmed.split('.');
  const dec = decPart.length < 2 ? decPart.padEnd(2, '0') : decPart;
  // Formata parte inteira com separador de milhar brasileiro
  const intFormatted = new Intl.NumberFormat('pt-BR').format(parseInt(intPart, 10));
  return `R$ ${intFormatted},${dec}`;
}

function formatDate(date) {
  if (!date) return '—';
  return new Date(date).toLocaleDateString('pt-BR');
}

function formatNumber(value) {
  const n = Number(value ?? 0);
  return n % 1 === 0 ? String(n) : n.toFixed(2).replace('.', ',');
}

// ── Paleta ────────────────────────────────────────────────────────────────────

const C = {
  black:      '#1A1A1A',
  gray:       '#6B7280',
  lightGray:  '#9CA3AF',
  divider:    '#E5E7EB',
  bgHeader:   '#F3F4F6',
  bgRow:      '#FAFAFA',
  accent:     '#E85D04',
  white:      '#FFFFFF',
  verde:      '#15803D',
  verdeLight: '#DCFCE7',
  vermelho:   '#DC2626',
  vermelhoLt: '#FEE2E2',
  azul:       '#1565C0',
  azulLight:  '#DBEAFE',
};

// ── Layout A4 portrait ────────────────────────────────────────────────────────

const MARGIN    = 32;
const PAGE_W    = 595.28;
const PAGE_H    = 841.89;
const CONTENT_W = PAGE_W - MARGIN * 2;

// ── Primitivos de desenho ─────────────────────────────────────────────────────

function fillRect(doc, x, y, w, h, color) {
  doc.fillColor(color).rect(x, y, w, h).fill();
}

function hline(doc, y, color = C.divider, lw = 0.5) {
  doc.strokeColor(color).lineWidth(lw)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
}

// ── Cabeçalho de página ───────────────────────────────────────────────────────

function drawPageHeader(doc, dados, logoPath) {
  const H = 70;

  fillRect(doc, 0, 0, PAGE_W, H, C.white);
  fillRect(doc, 0, 0, PAGE_W, 4, C.accent);

  // Logo
  const logoW = 90;
  const logoX = MARGIN;
  const logoY = 14;
  try {
    doc.image(logoPath, logoX, logoY, { height: 38, fit: [logoW, 38] });
  } catch (_) {
    doc.font('Helvetica-Bold').fontSize(14).fillColor(C.accent)
       .text('Visual', logoX, logoY + 5, { lineBreak: false });
    doc.font('Helvetica').fontSize(14).fillColor(C.black)
       .text(' Premium', logoX + 38, logoY + 5, { lineBreak: false });
    doc.font('Helvetica').fontSize(6).fillColor(C.lightGray)
       .text('comunicação visual', logoX, logoY + 22, { lineBreak: false });
  }

  // Dados da empresa
  const empresa = {
    nome:     'VISUAL PREMIUM',
    cnpjIe:   'CNPJ: 20.000.300/0001-88   IE: 9066233666',
    endereco: 'RUA GENERAL RONDON, 745 – NOVA RUSSIA – PONTA GROSSA – PR',
    telefone: 'Telefone: +55 (42) 3086-8600',
  };

  const infoX = logoX + logoW + 12;
  const infoW = 220;
  const infoY = 13;

  doc.font('Helvetica-Bold').fontSize(8).fillColor(C.black)
     .text(empresa.nome, infoX, infoY, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.cnpjIe, infoX, infoY + 11, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.endereco, infoX, infoY + 21, { width: infoW, lineBreak: true });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.telefone, infoX, infoY + 38, { width: infoW, lineBreak: false });

  // Título direito
  const titleX = infoX + infoW + 12;
  const titleW = PAGE_W - MARGIN - titleX;

  doc.strokeColor(C.divider).lineWidth(0.8)
     .moveTo(titleX - 6, 10).lineTo(titleX - 6, H - 10).stroke();

  // Número da OS limpo (sem sufixo interno #OC…)
  const numeroLimpo = dados.numeroOS.includes('#OC')
    ? dados.numeroOS.substring(0, dados.numeroOS.indexOf('#OC'))
    : dados.numeroOS;
  const tituloOS = /^\d+$/.test(numeroLimpo) ? `OS ${numeroLimpo}` : numeroLimpo;

  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.gray)
     .text('RELATÓRIO DE ORDEM DE SERVIÇO', titleX, 14, { width: titleW, align: 'right', lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(13).fillColor(C.black)
     .text(tituloOS, titleX, 28, { width: titleW, align: 'right', lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(`Gerado em ${formatDate(new Date())}`, titleX, 50, { width: titleW, align: 'right', lineBreak: false });

  doc.strokeColor(C.divider).lineWidth(1)
     .moveTo(0, H).lineTo(PAGE_W, H).stroke();
}

// ── Cards de resumo ───────────────────────────────────────────────────────────

function drawSummaryCards(doc, dados, y) {
  const saidas = dados.itens; // já filtrado no service

  const cards = [
    { label: 'Saídas',          value: String(saidas.length),            color: C.vermelho, bg: C.vermelhoLt },
    { label: 'Total em saídas', value: formatCurrency(dados.totalGeral), color: C.verde,    bg: C.verdeLight },
    { label: 'Fechada em',      value: formatDate(dados.fechadaEm),      color: C.gray,     bg: C.bgHeader   },
  ];

  const colW = CONTENT_W / 3;
  const boxH = 48;

  cards.forEach((card, i) => {
    const x = MARGIN + colW * i;
    fillRect(doc, x + 4, y, colW - 8, boxH, card.bg);

    doc.font('Helvetica').fontSize(7).fillColor(card.color)
       .text(card.label.toUpperCase(), x + 8, y + 8, { width: colW - 16, align: 'center', lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(11).fillColor(card.color)
       .text(card.value, x + 8, y + 22, { width: colW - 16, align: 'center', lineBreak: false });
  });

  // badge FECHADA
  const badgeW = 60;
  const badgeH = 16;
  const badgeX = PAGE_W - MARGIN - badgeW;
  const badgeY = y - 20;
  fillRect(doc, badgeX, badgeY, badgeW, badgeH, C.verde);
  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.white)
     .text('FECHADA', badgeX, badgeY + 5, { width: badgeW, align: 'center', lineBreak: false });

  return y + boxH + 12;
}

// ── Seção (título laranja) ────────────────────────────────────────────────────

function drawSectionHeader(doc, y, title) {
  fillRect(doc, MARGIN, y, CONTENT_W, 20, C.bgHeader);
  fillRect(doc, MARGIN, y, 4, 20, C.accent);
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.black)
     .text(title.toUpperCase(), MARGIN + 12, y + 7, { lineBreak: false });
  return y + 20;
}

// ── Cabeçalho da tabela de movimentações ──────────────────────────────────────

function drawMovTableHeader(doc, y, comPreco) {
  const HEADER_H = 20;
  fillRect(doc, MARGIN, y, CONTENT_W, HEADER_H, C.bgHeader);
  doc.strokeColor('#D1D5DB').lineWidth(0.8)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  doc.strokeColor('#D1D5DB').lineWidth(0.8)
     .moveTo(MARGIN, y + HEADER_H).lineTo(PAGE_W - MARGIN, y + HEADER_H).stroke();

  const cols = buildCols(comPreco);
  doc.font('Helvetica-Bold').fontSize(6.5).fillColor(C.gray);
  let cx = MARGIN;
  for (const col of cols) {
    doc.text(col.label, cx + 4, y + 7, { width: col.w - 8, align: col.align, lineBreak: false });
    cx += col.w;
  }
  return y + HEADER_H;
}

// ── Definição de colunas ──────────────────────────────────────────────────────

function buildCols(comPreco) {
  if (comPreco) {
    const qtdW   = 50;
    const unitW  = 72;
    const totalW = 72;
    const dataW  = 55;
    const matW   = CONTENT_W - qtdW - unitW - totalW - dataW;
    return [
      { label: 'Material', w: matW,   align: 'left'   },
      { label: 'Qtd.',     w: qtdW,   align: 'center' },
      { label: 'Unit.',    w: unitW,  align: 'right'  },
      { label: 'Total',    w: totalW, align: 'right'  },
      { label: 'Data',     w: dataW,  align: 'right'  },
    ];
  } else {
    const qtdW  = 72;
    const dataW = 60;
    const matW  = CONTENT_W - qtdW - dataW;
    return [
      { label: 'Material', w: matW,  align: 'left'   },
      { label: 'Qtd.',     w: qtdW,  align: 'center' },
      { label: 'Data',     w: dataW, align: 'right'  },
    ];
  }
}

// ── Linha de movimentação ─────────────────────────────────────────────────────

function drawMovRow(doc, item, idx, y, comPreco, pageH) {
  const FOOTER_RESERVE = 50;
  const ROW_PAD_V      = 5;
  const FONT_SZ        = 8.5;
  const SUB_SZ         = 7;
  const LINE_SUB       = 10; // altura de cada sublinha

  const cols  = buildCols(comPreco);
  const colW0 = cols[0].w - 8;

  // Monta as sublinhas abaixo do nome
  const sublines = [];
  const partes = [item.medida, item.espessura].filter(Boolean);
  if (partes.length > 0) sublines.push(partes.join(' \u00b7 '));
  if (item.unidade)      sublines.push(item.unidade);
  if (item.observacao)   sublines.push(`Obs: ${item.observacao}`);

  const nomeH = doc.heightOfString(item.material || '\u2014', { width: colW0, fontSize: FONT_SZ });
  const innerH = nomeH + sublines.length * LINE_SUB;
  const rowH   = Math.max(24, innerH + ROW_PAD_V * 2);

  if (y + rowH > pageH - FOOTER_RESERVE) return null; // sinaliza nova página

  if (idx % 2 === 0) fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgRow);

  const tyText   = y + ROW_PAD_V;
  const tySingle = y + (rowH - FONT_SZ) / 2;

  let cx = MARGIN;

  // Nome do material
  doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
     .text(item.material || '\u2014', cx + 4, tyText, { width: colW0, lineBreak: false });

  // Sublinhas: medida\u00b7espessura, unidade, obs
  let subY = tyText + nomeH + 1;
  for (const sub of sublines) {
    doc.font('Helvetica').fontSize(SUB_SZ).fillColor(C.lightGray)
       .text(sub, cx + 4, subY, { width: colW0, lineBreak: false });
    subY += LINE_SUB;
  }

  cx += cols[0].w;

  if (comPreco) {
    // Qtd
    const qtdLabel = item.unidade
      ? `${formatNumber(item.quantidade)} ${item.unidade}`
      : formatNumber(item.quantidade);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(qtdLabel, cx + 4, tySingle, { width: cols[1].w - 8, align: 'center', lineBreak: false });
    cx += cols[1].w;

    // Unit (precoUnitario já normalizado no service: usa pm2 quando pu=0)
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(item.precoUnitario > 0 ? formatCurrency(item.precoUnitario) : '—',
             cx + 4, tySingle, { width: cols[2].w - 8, align: 'right', lineBreak: false });
    if (item.usarM2 && item.precoUnitario > 0) {
      doc.font('Helvetica').fontSize(6.5).fillColor(C.lightGray)
         .text('(m²)', cx + 4, tySingle + FONT_SZ + 1, { width: cols[2].w - 8, align: 'right', lineBreak: false });
    }
    cx += cols[2].w;

    // Total
    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(item.total > 0 ? formatCurrency(item.total) : '—',
             cx + 4, tySingle, { width: cols[3].w - 8, align: 'right', lineBreak: false });
    cx += cols[3].w;

    // Data
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.lightGray)
       .text(formatDate(item.data), cx + 4, tySingle, { width: cols[4].w - 8, align: 'right', lineBreak: false });
  } else {
    // Qtd
    const qtdLabel = item.unidade
      ? `${formatNumber(item.quantidade)} ${item.unidade}`
      : formatNumber(item.quantidade);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(qtdLabel, cx + 4, tySingle, { width: cols[1].w - 8, align: 'center', lineBreak: false });
    cx += cols[1].w;

    // Data
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.lightGray)
       .text(formatDate(item.data), cx + 4, tySingle, { width: cols[2].w - 8, align: 'right', lineBreak: false });
  }

  // Linha divisória
  doc.strokeColor(C.divider).lineWidth(0.3)
     .moveTo(MARGIN, y + rowH).lineTo(PAGE_W - MARGIN, y + rowH).stroke();

  return y + rowH;
}

// ── Total geral (rodapé da seção de saídas) ───────────────────────────────────

function drawTotalRow(doc, totalGeral, y) {
  const rowH = 26;
  fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgHeader);
  doc.font('Helvetica-Bold').fontSize(9).fillColor(C.gray)
     .text('Total geral', MARGIN + 4, y + 9, { lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(11).fillColor(C.verde)
     .text(formatCurrency(totalGeral), MARGIN, y + 8, { width: CONTENT_W - 4, align: 'right', lineBreak: false });
  return y + rowH;
}

// ── Footer de página ──────────────────────────────────────────────────────────

function drawFooter(doc, pageNum, pageTotal) {
  const y = PAGE_H - 28;
  hline(doc, y - 8);
  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(`Gerado em ${formatDate(new Date())}   •   Visual Premium Estoque e Compras`,
           MARGIN, y, { width: CONTENT_W - 60, align: 'left' })
     .text(`Página ${pageNum} de ${pageTotal}`,
           MARGIN, y, { width: CONTENT_W, align: 'right' });
}

// ── Geração do documento ──────────────────────────────────────────────────────

function gerarDocumento(dados, logoPath, totalPaginas) {
  return new Promise((resolve, reject) => {
    const doc    = new PDFDocument({ size: 'A4', layout: 'portrait', margin: 0 });
    const chunks = [];
    let   pageNum = 1;

    doc.on('data',  (c) => chunks.push(c));
    doc.on('end',   () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const saidas = dados.itens; // apenas SAIDA, já filtrado pelo service

    const desenhar = () => {
      // ── Cabeçalho de página ──────────────────────────────────────────────
      drawPageHeader(doc, dados, logoPath);
      let y = 84;

      // ── Cards de resumo ──────────────────────────────────────────────────
      y = drawSummaryCards(doc, dados, y) + 4;

      // ── Seção: Saídas ────────────────────────────────────────────────────
      if (saidas.length > 0) {
        y = drawSectionHeader(doc, y, `Saídas de material  (${saidas.length} ${saidas.length === 1 ? 'item' : 'itens'})`);
        y = drawMovTableHeader(doc, y, true);

        for (let i = 0; i < saidas.length; i++) {
          const next = drawMovRow(doc, saidas[i], i, y, true, PAGE_H);
          if (next === null) {
            if (totalPaginas !== null) drawFooter(doc, pageNum, totalPaginas);
            pageNum++;
            doc.addPage();
            drawPageHeader(doc, dados, logoPath);
            y = drawMovTableHeader(doc, 84, true);
            const retry = drawMovRow(doc, saidas[i], i, y, true, PAGE_H);
            y = retry !== null ? retry : y + 22;
          } else {
            y = next;
          }
        }

        // Total geral de saídas
        if (dados.totalGeral > 0) {
          if (y + 26 > PAGE_H - 50) {
            if (totalPaginas !== null) drawFooter(doc, pageNum, totalPaginas);
            pageNum++;
            doc.addPage();
            drawPageHeader(doc, dados, logoPath);
            y = 84;
          }
          y = drawTotalRow(doc, dados.totalGeral, y) + 4;
        }
      }
    };

    if (totalPaginas === null) {
      // 1ª passagem: contar páginas
      doc.on('pageAdded', () => pageNum++);
      desenhar();
      doc.end();
    } else {
      // 2ª passagem: footers corretos
      const origAddPage = doc.addPage.bind(doc);
      doc.addPage = (...args) => {
        drawFooter(doc, pageNum, totalPaginas);
        pageNum++;
        return origAddPage(...args);
      };
      desenhar();
      drawFooter(doc, pageNum, totalPaginas);
      doc.end();
    }
  });
}

// ── Export principal ──────────────────────────────────────────────────────────

async function gerarPdfOS(numeroOS) {
  // Busca dados já prontos (saídas + totalGeral)
  const dados = await svc.dadosParaPDF(numeroOS);

  const logoPath = path.join(__dirname, '../../../frontend/assets/images/logoPreta.png');

  // 1ª passagem: descobrir total de páginas via contagem
  const totalReal = await new Promise((resolve, reject) => {
    const d     = new PDFDocument({ size: 'A4', layout: 'portrait', margin: 0 });
    let   count = 1;
    d.on('data',      () => {});
    d.on('pageAdded', () => count++);
    d.on('end',       () => resolve(count));
    d.on('error',     reject);

    gerarDocumentoContagem(dados, logoPath, d);
  });

  // 2ª passagem: gera PDF real com footers corretos
  return gerarDocumento(dados, logoPath, totalReal);
}

// Versão de contagem (sem footers, usa doc externo)
function gerarDocumentoContagem(dados, logoPath, doc) {
  const saidas = dados.itens;
  let pageNum  = 1;

  drawPageHeader(doc, dados, logoPath);
  let y = 84;
  drawSummaryCards(doc, dados, y);
  y += 64;

  if (saidas.length > 0) {
    y += 20 + 20; // section + header
    for (const item of saidas) {
      const rowH = Math.max(22, 10 + 10);
      if (y + rowH > PAGE_H - 50) { doc.addPage(); pageNum++; y = 84 + 20; }
      y += rowH;
    }
    if (dados.totalGeral > 0) {
      if (y + 26 > PAGE_H - 50) { doc.addPage(); pageNum++; y = 84; }
      y += 30;
    }
  }

  doc.end();
}

module.exports = { gerarPdfOS };