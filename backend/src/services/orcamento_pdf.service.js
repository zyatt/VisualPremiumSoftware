const PDFDocument = require('pdfkit');
const prisma      = require('../utils/prisma');
const path        = require('path');

function formatCurrency(value) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value ?? 0);
}

function formatDate(date) {
  if (!date) return '—';
  return new Date(date).toLocaleDateString('pt-BR');
}

function formatNumber(value) {
  return new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value ?? 0);
}

// Formata número sem decimais se for inteiro, com até 2 casas se tiver fração
function formatNumberSmart(value) {
  const v = value ?? 0;
  const isInt = Number.isInteger(v) || Math.abs(v - Math.round(v)) < 0.0001;
  return new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: isInt ? 0 : 2,
    maximumFractionDigits: isInt ? 0 : 2,
  }).format(v);
}

const C = {
  black:     '#1A1A1A',
  gray:      '#6B7280',
  lightGray: '#9CA3AF',
  divider:   '#E5E7EB',
  bgHeader:  '#F3F4F6',
  bgRow:     '#FAFAFA',
  accent:    '#E85D04',
  white:     '#FFFFFF',
  statusOk:  '#15803D',
  statusWarn:'#D97706',
  statusErr: '#DC2626',
};

const MARGIN    = 36;
const PAGE_W    = 595.28;
const PAGE_H    = 841.89;
const CONTENT_W = PAGE_W - MARGIN * 2;

function fillRect(doc, x, y, w, h, color) {
  doc.fillColor(color).rect(x, y, w, h).fill();
}

function hline(doc, y, color = C.divider, lw = 0.5) {
  doc.strokeColor(color).lineWidth(lw)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
}

function statusLabel(status) {
  if (status === 'FINALIZADO')   return { text: 'FINALIZADO',   color: C.statusOk };
  if (status === 'CANCELADO')    return { text: 'CANCELADO',    color: C.statusErr };
  return                                { text: 'EM ANDAMENTO', color: C.statusWarn };
}

function drawPageHeader(doc, oc, logoPath) {
  const H = 76;

  fillRect(doc, 0, 0, PAGE_W, H, C.white);
  fillRect(doc, 0, 0, PAGE_W, 4, C.accent);

  const logoW = 95;
  const logoX = MARGIN;
  const logoY = 14;
  try {
    doc.image(logoPath, logoX, logoY, { height: 42, fit: [logoW, 42] });
  } catch (_) {
    doc.font('Helvetica-Bold').fontSize(14).fillColor(C.accent)
       .text('Visual', logoX, logoY + 5, { lineBreak: false });
    doc.font('Helvetica').fontSize(14).fillColor(C.black)
       .text(' Premium', logoX + 38, logoY + 5, { lineBreak: false });
    doc.font('Helvetica').fontSize(6).fillColor(C.lightGray)
       .text('comunicação visual', logoX, logoY + 22, { lineBreak: false });
  }

  const isGuindaste = oc.logoEmpresa === 'GUINDASTE' || oc.empresa === 'VISUAL GUINDASTE';
  const empresa = isGuindaste
    ? {
        nome:     'VISUAL GUINDASTE LTDA',
        cnpjIe:   'CNPJ: 16.422.761/0001-71   IE: NÃO CONTRIBUINTE',
        endereco: 'RUA GENERAL RONDON, 745 – NOVA RUSSIA – PONTA GROSSA – PR',
        telefone: 'Telefone: +55 (42) 3086-8600',
      }
    : {
        nome:     'VISUAL PREMIUM',
        cnpjIe:   'CNPJ: 20.000.300/0001-88   IE: 9066233666',
        endereco: 'RUA GENERAL RONDON, 745 – NOVA RUSSIA – PONTA GROSSA – PR',
        telefone: 'Telefone: +55 (42) 3086-8600',
      };

  const baseInfoX   = logoX + logoW + 12;
  const extraOffset = isGuindaste ? 35 : 0;
  const infoX       = baseInfoX + extraOffset;
  const infoW       = 220;
  const infoY       = 13;

  doc.font('Helvetica-Bold').fontSize(8).fillColor(C.black)
     .text(empresa.nome, infoX, infoY, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.cnpjIe, infoX, infoY + 11, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.endereco, infoX, infoY + 21, { width: infoW, lineBreak: true });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.telefone, infoX, infoY + 38, { width: infoW, lineBreak: false });

  const ocX = infoX + infoW + 10;
  const ocW = PAGE_W - MARGIN - ocX;

  doc.strokeColor(C.divider).lineWidth(0.8)
     .moveTo(ocX - 6, 10).lineTo(ocX - 6, H - 10).stroke();

  // Se for OC real (tem id numérico), mostra label de OC + número; caso contrário mostra ORÇAMENTO
  const isOC = oc._isOrdemCompra === true;
  if (isOC) {
    doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.gray)
       .text('ORDEM DE COMPRA', ocX, 14, { width: ocW, align: 'right', lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(28).fillColor(C.black)
       .text(`#${oc.id}`, ocX, 22, { width: ocW, align: 'right', lineBreak: false });
    const st = statusLabel(oc.status);
    doc.font('Helvetica-Bold').fontSize(6.5).fillColor(st.color)
       .text(st.text, ocX, 56, { width: ocW, align: 'right', lineBreak: false });
  } else {
    doc.font('Helvetica-Bold').fontSize(13).fillColor(C.accent)
       .text('ORÇAMENTO', ocX, 24, { width: ocW, align: 'right', lineBreak: false });
    const dataHoje = formatDate(new Date());
    doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
       .text(dataHoje, ocX, 44, { width: ocW, align: 'right', lineBreak: false });
  }

  doc.strokeColor(C.divider).lineWidth(1)
     .moveTo(0, H).lineTo(PAGE_W, H).stroke();
}

function drawSectionHeader(doc, y, title) {
  fillRect(doc, MARGIN, y, CONTENT_W, 20, C.bgHeader);
  fillRect(doc, MARGIN, y, 4, 20, C.accent);
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.black)
     .text(title.toUpperCase(), MARGIN + 12, y + 7);
}

function drawInfoRow(doc, y, label, value) {
  doc.font('Helvetica').fontSize(7.5).fillColor(C.lightGray)
     .text(label, MARGIN, y, { width: 130 });
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.black)
     .text(value || '—', MARGIN + 135, y, { width: CONTENT_W - 135 });
}

function drawOsBadges(doc, numerosOS, startY) {
  if (!numerosOS || numerosOS.length === 0) return startY;

  doc.font('Helvetica').fontSize(7.5).fillColor(C.lightGray)
     .text('Números de OS', MARGIN, startY, { width: 130 });

  let bx = MARGIN + 135;
  const by = startY - 1;

  for (const os of numerosOS) {
    const text  = typeof os === 'object' ? os.numeroOS : os;
    const tw    = doc.widthOfString(text, { fontSize: 7 }) + 12;
    fillRect(doc, bx, by, tw, 13, C.accent + '1A');
    doc.rect(bx, by, tw, 13).strokeColor(C.accent + '55').lineWidth(0.5).stroke();
    doc.font('Helvetica-Bold').fontSize(7).fillColor(C.accent)
       .text(text, bx + 6, by + 3, { width: tw - 12, lineBreak: false });
    bx += tw + 5;
  }

  return startY;
}

function drawTotalBox(doc, y, valorTotal) {
  const boxW = 200;
  const boxH = 32;
  const boxX = PAGE_W - MARGIN - boxW;

  fillRect(doc, boxX, y, boxW, boxH, C.bgHeader);

  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text('TOTAL GERAL', boxX + 10, y + 6, { width: boxW - 20, align: 'left' });
  doc.font('Helvetica-Bold').fontSize(13).fillColor(C.black)
     .text(formatCurrency(valorTotal), boxX + 10, y + 14, { width: boxW - 20, align: 'right' });

  return y + boxH;
}

function drawItensTable(doc, itens, startY) {
  const cols = [
    { key: 'material',   label: 'MATERIAL',    w: 155, hAlign: 'left',   cAlign: 'left',   pad: 5 },
    { key: 'qtd',        label: 'QTD',         w: 100, hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'unidade',    label: 'UNIDADE',     w: 44,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'precoUnit',  label: 'PREÇO UNIT.', w: 78,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'precoM2',    label: 'PREÇO M²',    w: 68,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'precoTotal', label: 'TOTAL',       w: 78,  hAlign: 'center', cAlign: 'right',  pad: 5 },
  ];

  let cx = MARGIN;
  for (const col of cols) { col.x = cx; cx += col.w; }

  const HEADER_H      = 20;
  const ROW_PAD_V     = 5;
  const FONT_SZ       = 7;
  const FOOTER_RESERVE = 130;

  let y = startY;

  const drawColDividers = (rowY, rowH) => {
    doc.strokeColor('#E0E0E0').lineWidth(0.4);
    for (let i = 1; i < cols.length; i++) {
      doc.moveTo(cols[i].x, rowY + 3).lineTo(cols[i].x, rowY + rowH - 3).stroke();
    }
  };

  const drawHeader = () => {
    fillRect(doc, MARGIN, y, CONTENT_W, HEADER_H, C.bgHeader);
    doc.strokeColor('#D1D5DB').lineWidth(0.8)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
    doc.strokeColor('#D1D5DB').lineWidth(0.8)
       .moveTo(MARGIN, y + HEADER_H).lineTo(PAGE_W - MARGIN, y + HEADER_H).stroke();

    doc.font('Helvetica-Bold').fontSize(7).fillColor(C.gray);
    for (const col of cols) {
      doc.text(col.label, col.x + col.pad, y + (HEADER_H - 7) / 2,
               { width: col.w - col.pad * 2, align: col.hAlign, lineBreak: false });
    }
    drawColDividers(y, HEADER_H);
    y += HEADER_H;
  };

  drawHeader();

  itens.forEach((item, idx) => {
    const nome    = item.material?.nome ?? `Material ${item.materialId}`;
    const unidade = item.material?.unidade ?? '—';
    const descricao = item.descricaoItem?.trim() || null;

    doc.font('Helvetica-Bold').fontSize(FONT_SZ);
    const matH  = doc.heightOfString(nome, { width: cols[0].w - cols[0].pad * 2 });
    const descH = descricao
      ? doc.font('Helvetica').fontSize(FONT_SZ - 0.5).heightOfString(descricao, { width: cols[0].w - cols[0].pad * 2 }) + 3
      : 0;
    const rowH  = Math.max(20, matH + descH + ROW_PAD_V * 2);

    if (y + rowH > PAGE_H - FOOTER_RESERVE) {
      drawFooter(doc, doc.bufferedPageRange().count);
      doc.addPage();
      y = MARGIN;
      drawHeader();
    }

    if (idx % 2 === 0) fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgRow);

    const tySingle = y + (rowH - FONT_SZ) / 2;
    const tyMulti  = y + ROW_PAD_V;

    const [C0, C1, C2, C3, C4, C5] = cols;

    doc.save();
    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(nome, C0.x + C0.pad, tyMulti, { width: C0.w - C0.pad * 2, align: 'left', lineBreak: true });
    if (descricao) {
      const descY = tyMulti + matH + 2;
      doc.font('Helvetica').fontSize(FONT_SZ - 0.5).fillColor(C.gray)
         .text(descricao, C0.x + C0.pad, descY, { width: C0.w - C0.pad * 2, align: 'left', lineBreak: true });
    }
    doc.restore();

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.black)
       .text(formatNumberSmart(item.quantidade), C1.x + C1.pad, tySingle,
             { width: C1.w - C1.pad * 2, align: 'center', lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.black)
       .text(unidade, C2.x + C2.pad, tySingle,
             { width: C2.w - C2.pad * 2, align: 'center', lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(formatCurrency(item.precoUnitario), C3.x + C3.pad, tySingle,
             { width: C3.w - C3.pad * 2, align: 'center', lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(item.precoMetroQuadrado != null ? formatCurrency(item.precoMetroQuadrado) : '—',
             C4.x + C4.pad, tySingle,
             { width: C4.w - C4.pad * 2, align: 'center', lineBreak: false });

    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(formatCurrency(item.precoTotal), C5.x + C5.pad, tySingle,
             { width: C5.w - C5.pad * 2, align: 'right', lineBreak: false });

    drawColDividers(y, rowH);
    y += rowH;

    doc.strokeColor(C.divider).lineWidth(0.4)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  });

  return y;
}

function drawObservacoes(doc, observacoes) {
  if (!observacoes) return;

  const footerY = PAGE_H - 44;
  const maxW    = CONTENT_W / 2 - 8;
  const lineH   = 10;
  const padV    = 7;
  const padH    = 8;

  const linhas  = observacoes.split('\n').filter(Boolean);
  const blockH  = padV + 10 + 3 + Math.max(linhas.length, 1) * lineH + padV;
  const blockY  = footerY - blockH - 6;

  fillRect(doc, MARGIN, blockY, maxW, blockH, C.bgHeader);
  fillRect(doc, MARGIN, blockY, 3, blockH, C.accent);

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.black)
     .text('Observações', MARGIN + padH, blockY + padV, { width: maxW - padH * 2 });

  let ty = blockY + padV + 11;
  for (const linha of linhas) {
    doc.font('Helvetica').fontSize(7).fillColor(C.black)
       .text(`• ${linha}`, MARGIN + padH, ty, { width: maxW - padH * 2, lineBreak: true });
    ty += lineH;
  }
}

function drawInfoFixa(doc) {
  const footerY = PAGE_H - 44;
  const blockW  = CONTENT_W / 2 - 8;
  const blockX  = MARGIN + CONTENT_W / 2 + 8;
  const lineH   = 10;
  const padV    = 7;
  const padH    = 8;

  const linhas = [
    'O número da OC deverá ser inserido no campo',
    'de dados adicionais da nota fiscal.',
    '',
    'Horário de entrega:',
    'Segunda à Sexta  |  08:00 – 11:45  /  13:45 – 17:45',
  ];

  const blockH = padV + 10 + 3 + linhas.length * lineH + padV;
  const blockY = footerY - blockH - 6;

  fillRect(doc, blockX, blockY, blockW, blockH, '#FFF7ED');
  fillRect(doc, blockX, blockY, 3, blockH, C.accent);

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.accent)
     .text('⚠  INDISPENSÁVEL', blockX + padH, blockY + padV, { width: blockW - padH * 2, lineBreak: false });

  let ty = blockY + padV + 11;
  for (const linha of linhas) {
    if (linha === '') { ty += lineH * 0.4; continue; }
    const isBold = linha.startsWith('Horário');
    doc.font(isBold ? 'Helvetica-Bold' : 'Helvetica').fontSize(7).fillColor(C.black)
       .text(linha, blockX + padH, ty, { width: blockW - padH * 2, lineBreak: false });
    ty += lineH;
  }
}

function drawFooter(doc, pageNum, empresaNome = 'Visual Premium') {
  const y = PAGE_H - 36;
  hline(doc, y - 8);
  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(`Gerado em ${formatDate(new Date())}   •   ${empresaNome} Estoque e Compras`,
           MARGIN, y, { width: CONTENT_W - 60, align: 'left' })
     .text(`Página ${pageNum}`, MARGIN, y, { width: CONTENT_W, align: 'right' });
}

// ─── Gerador de PDF de Orçamento (dados do cliente, sem ID do banco) ──────────

/**
 * Desenha a tabela de comparação de um único item do orçamento.
 * Mostra todos os fornecedores vinculados, destaca o menor preço,
 * e exibe o total por fornecedor.
 *
 * Retorna o novo valor de `y` após o bloco.
 */
function drawItemComparacao(doc, item, idx, startY) {
  const FOOTER_RESERVE = 120;
  const FONT_SZ        = 7;
  const ROW_H          = 20;
  const HEADER_H       = 22;
  const COL_HDR_H      = 13;
  const BLOCK_PAD      = 10;

  const qtd       = item.quantidade ?? 1;
  const usarM2    = item.modoOrcamento === 'metroQuadrado';
  const descricao = item.descricao?.trim() || null;
  const unidade   = item.materialUnidade ?? '';

  // Monta texto legível de quantidade
  // Ex: "Quantidade: 3,50 m²" ou "Quantidade: 2 unidades"
  const unidadeLabel = usarM2
    ? 'm²'
    : (unidade || 'unidade' + (qtd !== 1 ? 's' : ''));
  const qtdTexto = `Quantidade: ${formatNumberSmart(qtd)} ${unidadeLabel}`;

  // Normaliza a lista de fornecedores com seus preços
  const precosMap = item.precos ?? {};
  const fornList  = Object.entries(precosMap).map(([fId, pf]) => {
    const preco   = pf.preco   ?? null;
    const precoM2 = pf.precoM2 ?? null;
    // usa m² se o item está em modo m², ou se só tem preço m² cadastrado
    const usarM2f    = usarM2 || (item.modoOrcamento == null && precoM2 != null && precoM2 > 0 && !preco);
    const precoBase  = usarM2f ? precoM2 : preco;
    const precoTotal = precoBase != null ? precoBase * qtd : null;
    return {
      fornecedorId:   fId,
      fornecedorNome: pf.fornecedorNome ?? `Fornecedor ${fId}`,
      preco,
      precoM2,
      precoTotal,
    };
  });

  // Menor preço total entre os que têm preço informado
  const comPreco   = fornList.filter((f) => f.precoTotal != null);
  const menorTotal = comPreco.length > 0 ? Math.min(...comPreco.map((f) => f.precoTotal)) : null;

  // Ordena: menor preço primeiro, sem preço no final
  fornList.sort((a, b) => {
    if (a.precoTotal == null && b.precoTotal == null) return 0;
    if (a.precoTotal == null) return 1;
    if (b.precoTotal == null) return -1;
    return a.precoTotal - b.precoTotal;
  });

  // Totais por fornecedor (retornados para o acumulador global)
  const totaisForn = {}; // { fornecedorNome: total }
  fornList.forEach((f) => {
    if (f.precoTotal != null) totaisForn[f.fornecedorNome] = f.precoTotal;
  });

  // Estima altura do bloco
  const descH  = descricao ? 9 : 0;
  const nForn  = Math.max(fornList.length, 1);
  const blockH = BLOCK_PAD + HEADER_H + descH + COL_HDR_H + nForn * ROW_H + BLOCK_PAD;

  // Quebra de página se necessário
  let y = startY;
  if (y + blockH > PAGE_H - FOOTER_RESERVE) {
    drawFooter(doc, doc.bufferedPageRange().count);
    doc.addPage();
    y = MARGIN + 10;
  }

  // ── Faixa do material ─────────────────────────────────────────────────
  fillRect(doc, MARGIN, y, CONTENT_W, HEADER_H + descH, C.bgHeader);
  fillRect(doc, MARGIN, y, 3, HEADER_H + descH, C.accent);

  // Nome do material
  doc.font('Helvetica-Bold').fontSize(8).fillColor(C.black)
     .text(item.materialNome, MARGIN + 10, y + 5, { width: 300, lineBreak: false });

  // Quantidade — texto completo, legível, alinhado à direita da faixa
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(qtdTexto, MARGIN + 10, y + 13, { width: CONTENT_W - 20, align: 'right', lineBreak: false });

  // Descrição (material específico) — abaixo do nome
  if (descricao) {
    doc.font('Helvetica').fontSize(6.5).fillColor(C.gray)
       .text(descricao, MARGIN + 10, y + HEADER_H - 8, { width: CONTENT_W - 20, lineBreak: false });
  }

  y += HEADER_H + descH;

  // ── Cabeçalho das colunas ─────────────────────────────────────────────
  // Colunas: Fornecedor | Preço Unit. | Preço M² | Total | Status
  const colNome   = { x: MARGIN + 6,   w: 195 };
  const colPUnit  = { x: MARGIN + 205, w: 85  };
  const colPM2    = { x: MARGIN + 293, w: 85  };
  const colTotal  = { x: MARGIN + 381, w: 90  };
  const colStatus = { x: MARGIN + 474, w: 49  };

  fillRect(doc, MARGIN, y, CONTENT_W, COL_HDR_H, '#EBEBEB');
  doc.font('Helvetica-Bold').fontSize(6).fillColor(C.gray);
  doc.text('FORNECEDOR',  colNome.x,   y + 3, { width: colNome.w,   lineBreak: false });
  doc.text('PREÇO UNIT.', colPUnit.x,  y + 3, { width: colPUnit.w,  align: 'center', lineBreak: false });
  doc.text('PREÇO M²',    colPM2.x,    y + 3, { width: colPM2.w,    align: 'center', lineBreak: false });
  doc.text('TOTAL',       colTotal.x,  y + 3, { width: colTotal.w,  align: 'right',  lineBreak: false });
  y += COL_HDR_H;

  // ── Linhas de fornecedores ────────────────────────────────────────────
  if (fornList.length === 0) {
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.lightGray)
       .text('Nenhum fornecedor vinculado.', MARGIN + 6, y + 4, { width: CONTENT_W - 12, lineBreak: false });
    y += ROW_H;
  } else {
    fornList.forEach((forn) => {
      const isMenor = forn.precoTotal != null && forn.precoTotal === menorTotal;

      // Fundo branco para todas as linhas
      fillRect(doc, MARGIN, y, CONTENT_W, ROW_H, C.white);

      const ty = y + (ROW_H - FONT_SZ) / 2;

      // Nome do fornecedor
      doc.font(isMenor ? 'Helvetica-Bold' : 'Helvetica').fontSize(FONT_SZ).fillColor(C.black)
         .text(forn.fornecedorNome, colNome.x, ty, { width: colNome.w, lineBreak: false });

      // Preço unitário
      doc.font('Helvetica').fontSize(FONT_SZ)
         .fillColor(forn.preco != null ? C.black : C.lightGray)
         .text(forn.preco != null ? formatCurrency(forn.preco) : '—',
               colPUnit.x, ty, { width: colPUnit.w, align: 'center', lineBreak: false });

      // Preço M²
      doc.font('Helvetica').fontSize(FONT_SZ)
         .fillColor(forn.precoM2 != null ? C.black : C.lightGray)
         .text(forn.precoM2 != null ? formatCurrency(forn.precoM2) : '—',
               colPM2.x, ty, { width: colPM2.w, align: 'center', lineBreak: false });

      // Total — verde se menor, preto normal, cinza se sem preço
      const totalColor = isMenor ? C.statusOk : (forn.precoTotal != null ? C.black : C.lightGray);
      doc.font(isMenor ? 'Helvetica-Bold' : 'Helvetica').fontSize(FONT_SZ).fillColor(totalColor)
         .text(forn.precoTotal != null ? formatCurrency(forn.precoTotal) : '—',
               colTotal.x, ty, { width: colTotal.w, align: 'right', lineBreak: false });

      // Coluna STATUS — badge "✓ MENOR" dedicada, sem risco de corte
      if (isMenor) {
        const badgeX = colStatus.x + 2;
        const badgeW = colStatus.w - 4;
        const badgeH = 11;
        const badgeY = y + (ROW_H - badgeH) / 2;
        fillRect(doc, badgeX, badgeY, badgeW, badgeH, '#D1FAE5');
        doc.rect(badgeX, badgeY, badgeW, badgeH)
           .strokeColor('#6EE7B7').lineWidth(0.4).stroke();
        doc.font('Helvetica-Bold').fontSize(5.5).fillColor(C.statusOk)
           .text('MENOR', badgeX, badgeY + 2.5, { width: badgeW, align: 'center', lineBreak: false });
      }

      // Linha divisória sutil
      doc.strokeColor(C.divider).lineWidth(0.3)
         .moveTo(MARGIN, y + ROW_H).lineTo(PAGE_W - MARGIN, y + ROW_H).stroke();

      y += ROW_H;
    });

    // ── Linha de médias ───────────────────────────────────────────────────
    const comPrecoUnit = fornList.filter((f) => f.preco   != null);
    const comPrecoM2   = fornList.filter((f) => f.precoM2 != null);
    const comTotal     = fornList.filter((f) => f.precoTotal != null);

    const mediaUnit  = comPrecoUnit.length > 0 ? comPrecoUnit.reduce((s, f) => s + f.preco,   0) / comPrecoUnit.length : null;
    const mediaM2    = comPrecoM2.length   > 0 ? comPrecoM2.reduce((s, f)   => s + f.precoM2, 0) / comPrecoM2.length   : null;
    const mediaTotal = comTotal.length     > 0 ? comTotal.reduce((s, f)     => s + f.precoTotal, 0) / comTotal.length   : null;

    const MEDIA_H = 14;
    fillRect(doc, MARGIN, y, CONTENT_W, MEDIA_H, '#FFF7ED');

    // Borda superior sutil em laranja
    doc.strokeColor('#FDBA74').lineWidth(0.4)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();

    const tym = y + (MEDIA_H - FONT_SZ) / 2;

    doc.font('Helvetica-Bold').fontSize(6).fillColor('#EA580C')
       .text('MÉDIA', colNome.x, tym, { width: colNome.w, lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(mediaUnit != null ? '#EA580C' : C.lightGray)
       .text(mediaUnit != null ? formatCurrency(mediaUnit) : '—',
             colPUnit.x, tym, { width: colPUnit.w, align: 'center', lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(mediaM2 != null ? '#EA580C' : C.lightGray)
       .text(mediaM2 != null ? formatCurrency(mediaM2) : '—',
             colPM2.x, tym, { width: colPM2.w, align: 'center', lineBreak: false });

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(mediaTotal != null ? '#EA580C' : C.lightGray)
       .text(mediaTotal != null ? formatCurrency(mediaTotal) : '—',
             colTotal.x, tym, { width: colTotal.w, align: 'right', lineBreak: false });

    doc.strokeColor('#FDBA74').lineWidth(0.4)
       .moveTo(MARGIN, y + MEDIA_H).lineTo(PAGE_W - MARGIN, y + MEDIA_H).stroke();

    y += MEDIA_H;
  }

  y += BLOCK_PAD;
  return { y, totaisForn };
}

async function gerarPdfDeItens(dados) {
  const { titulo = 'Orçamento', itens = [] } = dados;

  return new Promise((resolve, reject) => {
    const doc    = new PDFDocument({ size: 'A4', margin: 0, bufferPages: true });
    const chunks = [];

    doc.on('data',  (chunk) => chunks.push(chunk));
    doc.on('end',   () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const logoPath = path.join(__dirname, '../../../frontend/assets/images/logoPreta.png');

    const orcFake = { _isOrdemCompra: false, logoEmpresa: 'PREMIUM', empresa: 'VISUAL PREMIUM' };
    drawPageHeader(doc, orcFake, logoPath);
    let y = 90;

    if (itens.length === 0) {
      drawSectionHeader(doc, y, 'Comparativo de Preços — 0 materiais');
      y += 26;
      doc.font('Helvetica').fontSize(9).fillColor(C.gray)
         .text('Nenhum item neste orçamento.', MARGIN, y, { width: CONTENT_W, align: 'center' });
      y += 20;
    } else {
      const totalMateriais = itens.length;

      // ── Pré-calcula totais por fornecedor (primeira passagem, sem desenhar) ───
      // Estrutura: { nome: { total, materiaisVinculados, materiaisComPreco } }
      const totaisMap = {};
      itens.forEach((item) => {
        const qtd    = item.quantidade ?? 1;
        const usarM2 = item.modoOrcamento === 'metroQuadrado';
        Object.entries(item.precos ?? {}).forEach(([, pf]) => {
          const nome = pf.fornecedorNome ?? 'Desconhecido';
          if (!totaisMap[nome]) {
            totaisMap[nome] = { total: 0, materiaisVinculados: 0, materiaisComPreco: 0 };
          }
          totaisMap[nome].materiaisVinculados += 1;
          const preco   = pf.preco   ?? null;
          const precoM2 = pf.precoM2 ?? null;
          const usarM2f = usarM2 || (item.modoOrcamento == null && precoM2 != null && precoM2 > 0 && !preco);
          const precoBase = usarM2f ? precoM2 : preco;
          if (precoBase != null) {
            totaisMap[nome].total            += precoBase * qtd;
            totaisMap[nome].materiaisComPreco += 1;
          }
        });
      });

      const todosEntries = Object.entries(totaisMap)
        .sort((a, b) => {
          // sem nenhum preço vai pro final; dentro do grupo ordena por total
          if (a[1].total === 0 && b[1].total === 0) return 0;
          if (a[1].total === 0) return 1;
          if (b[1].total === 0) return -1;
          return a[1].total - b[1].total;
        });

      // ── Seção de Totais por Fornecedor (no topo) ─────────────────────────────
      if (todosEntries.length > 0) {
        const rowH       = 20;
        const tableLines = todosEntries.length;
        const tableH     = 26 + 13 + tableLines * rowH + 10;

        if (y + tableH > PAGE_H - 60) {
          drawFooter(doc, doc.bufferedPageRange().count);
          doc.addPage();
          y = MARGIN + 10;
        }

        drawSectionHeader(doc, y, 'Totais por Fornecedor — resumo comparativo');
        y += 26;

        // Colunas: Fornecedor | Materiais | Total Acumulado | Status
        const colForn  = { x: MARGIN + 8,   w: 220 };
        const colMats  = { x: MARGIN + 232,  w: 110 };
        const colTotal = { x: MARGIN + 346,  w: 130 };
        const colBadge = { x: MARGIN + 479,  w: 44  };

        // Cabeçalho
        fillRect(doc, MARGIN, y, CONTENT_W, 13, '#EBEBEB');
        doc.font('Helvetica-Bold').fontSize(6).fillColor(C.gray);
        doc.text('FORNECEDOR',       colForn.x,  y + 3, { width: colForn.w,  lineBreak: false });
        doc.text('MATERIAIS',        colMats.x,  y + 3, { width: colMats.w,  align: 'center', lineBreak: false });
        doc.text('TOTAL ACUMULADO',  colTotal.x, y + 3, { width: colTotal.w, align: 'right',  lineBreak: false });
        y += 13;

        const menorTotalGeral = todosEntries.find(([, v]) => v.total > 0)?.[1]?.total ?? null;

        todosEntries.forEach(([nome, info], ri) => {
          const { total, materiaisVinculados, materiaisComPreco } = info;
          const isMenor      = total > 0 && total === menorTotalGeral;
          const cobreTotal   = materiaisVinculados >= totalMateriais;
          const temPrecTodos = materiaisComPreco   >= totalMateriais;

          if (ri % 2 === 0) fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgRow);

          const ty = y + (rowH - 7) / 2;

          // Nome do fornecedor
          doc.font(isMenor ? 'Helvetica-Bold' : 'Helvetica').fontSize(7)
             .fillColor(isMenor ? C.statusOk : C.black)
             .text(nome, colForn.x, ty, { width: colForn.w, lineBreak: false });

          // ── Coluna Materiais: "X/Total" + sub-label se incompleto ────────
          const matsLabel = `${materiaisVinculados}/${totalMateriais}`;
          const matsColor = cobreTotal
            ? (temPrecTodos ? C.black : C.statusWarn)
            : C.statusErr;

          doc.font('Helvetica-Bold').fontSize(7).fillColor(matsColor)
             .text(matsLabel, colMats.x, cobreTotal ? ty : ty - 2,
                   { width: colMats.w, align: 'center', lineBreak: false });

          if (!cobreTotal) {
            doc.font('Helvetica').fontSize(5.5).fillColor(C.statusErr)
               .text('incompleto', colMats.x, ty + 6,
                     { width: colMats.w, align: 'center', lineBreak: false });
          } else if (!temPrecTodos) {
            const semPreco = materiaisVinculados - materiaisComPreco;
            doc.font('Helvetica').fontSize(5.5).fillColor(C.statusWarn)
               .text(`${semPreco} sem preço`, colMats.x, ty + 6,
                     { width: colMats.w, align: 'center', lineBreak: false });
          }

          // Total acumulado
          doc.font('Helvetica-Bold').fontSize(7)
             .fillColor(isMenor ? C.statusOk : (total > 0 ? C.black : C.lightGray))
             .text(total > 0 ? formatCurrency(total) : '—',
                   colTotal.x, ty, { width: colTotal.w, align: 'right', lineBreak: false });

          // Badge "MENOR TOTAL"
          if (isMenor) {
            const bx = colBadge.x + 2;
            const bw = colBadge.w - 4;
            const bh = 11;
            const by = y + (rowH - bh) / 2;
            fillRect(doc, bx, by, bw, bh, '#D1FAE5');
            doc.rect(bx, by, bw, bh).strokeColor('#6EE7B7').lineWidth(0.4).stroke();
            doc.font('Helvetica-Bold').fontSize(5.5).fillColor(C.statusOk)
               .text('MENOR TOTAL', bx, by + 2.5, { width: bw, align: 'center', lineBreak: false });
          }

          doc.strokeColor(C.divider).lineWidth(0.3)
             .moveTo(MARGIN, y + rowH).lineTo(PAGE_W - MARGIN, y + rowH).stroke();
          y += rowH;
        });

        y += 14;
        hline(doc, y, '#D1D5DB', 0.8);
        y += 14;
      }

      // ── Seção dos itens individuais ───────────────────────────────────────────
      drawSectionHeader(doc, y, `Comparativo de Preços — ${itens.length} ${itens.length === 1 ? 'material' : 'materiais'}`);
      y += 26;

      itens.forEach((item, idx) => {
        const result = drawItemComparacao(doc, item, idx, y);
        y = result.y;
      });

      hline(doc, y, '#D1D5DB', 0.8);
      y += 10;
    }

    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(range.start + i);
      drawFooter(doc, i + 1, 'Visual Premium');
    }

    doc.end();
  });
}

// ─── Gerador de PDF de Ordem de Compra (por ID do banco) ─────────────────────

const ordemCompraPdfService = {
  async gerarPdf(id) {
    const oc = await prisma.ordemCompra.findUnique({
      where: { id: Number(id) },
      include: {
        fornecedor: true,
        usuario:    { select: { id: true, nome: true } },
        itens: {
          include: { material: true },
        },
        numerosOS: true,
      },
    });

    if (!oc) throw { status: 404, message: 'Ordem de compra não encontrada' };

    return new Promise((resolve, reject) => {
      const doc    = new PDFDocument({ size: 'A4', margin: 0, bufferPages: true });
      const chunks = [];

      doc.on('data',  (chunk) => chunks.push(chunk));
      doc.on('end',   () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      const logoFile = (oc.logoEmpresa === 'GUINDASTE' || oc.empresa === 'VISUAL GUINDASTE') ? 'logoGuindaste.jpeg' : 'logoPreta.png';
      const logoPath = path.join(__dirname, '../../../frontend/assets/images/', logoFile);

      drawPageHeader(doc, { ...oc, _isOrdemCompra: true }, logoPath);
      let y = 90;

      drawSectionHeader(doc, y, 'Informações da Ordem de Compra');
      y += 26;

      const infoRows = [
        ['Nº da OC',            `#${oc.id}`],
        ['Status',              statusLabel(oc.status).text],
        ['Data',                formatDate(oc.data)],
        ['Fornecedor',          oc.fornecedor?.nomeFantasia ?? oc.fornecedor?.nome ?? '—'],
        ['Requisitante',        oc.requisitante || '—'],
        ['Empresa',             oc.empresa || '—'],
        ['Forma de Pagamento',  oc.formaPagamento || '—'],
        ['Prazo de Pagamento',  oc.prazoPagamento || '—'],
      ];

      for (const [label, value] of infoRows) {
        drawInfoRow(doc, y, label, value);
        y += 14;
      }


      y += 6;
      hline(doc, y);
      y += 10;

      const valorTotal = oc.itens.reduce((s, i) => s + Number(i.precoTotal), 0);
      y = drawTotalBox(doc, y, valorTotal);
      y += 12;

      drawSectionHeader(doc, y, `Itens da OC (${oc.itens.length})`);
      y += 24;

      if (oc.itens.length === 0) {
        doc.font('Helvetica').fontSize(9).fillColor(C.gray)
           .text('Nenhum item nesta Ordem de Compra.', MARGIN, y, { width: CONTENT_W, align: 'center' });
        y += 20;
      } else {
        y = drawItensTable(doc, oc.itens, y);
        y += 10;

        hline(doc, y, '#D1D5DB', 0.8);
        y += 8;

        doc.font('Helvetica').fontSize(7).fillColor(C.gray)
           .text('Subtotal dos itens:', MARGIN, y);
        doc.font('Helvetica-Bold').fontSize(9).fillColor(C.black)
           .text(formatCurrency(valorTotal), MARGIN, y - 1, { width: CONTENT_W, align: 'right' });
      }

      const range       = doc.bufferedPageRange();
      const lastPageIdx = range.start + range.count - 1;
      doc.switchToPage(lastPageIdx);
      drawObservacoes(doc, oc.observacoes);
      drawInfoFixa(doc);

      const empresaNomeRodape = (oc.logoEmpresa === 'GUINDASTE' || oc.empresa === 'VISUAL GUINDASTE') ? 'Visual Guindaste' : 'Visual Premium';
      for (let i = 0; i < range.count; i++) {
        doc.switchToPage(range.start + i);
        drawFooter(doc, i + 1, empresaNomeRodape);
      }

      doc.end();
    });
  },
};

module.exports = { ...ordemCompraPdfService, gerarPdfDeItens };