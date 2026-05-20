const PDFDocument = require('pdfkit');
const path        = require('path');

// ── Formatters ────────────────────────────────────────────────────────────────

function formatCurrency(value) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value ?? 0);
}

function formatDate(date) {
  if (!date) return '—';
  return new Date(date).toLocaleDateString('pt-BR');
}

function formatDateTime(date) {
  if (!date) return '—';
  return new Date(date).toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function formatNumber(value) {
  return new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value ?? 0);
}

// ── Palette ───────────────────────────────────────────────────────────────────

const C = {
  black:       '#1A1A1A',
  gray:        '#6B7280',
  lightGray:   '#9CA3AF',
  divider:     '#E5E7EB',
  bgHeader:    '#F3F4F6',
  bgRow:       '#FAFAFA',
  accent:      '#E85D04',
  accentBg:    '#FFF7ED',
  blue:        '#E85D04',   // era azul escuro — agora laranja
  blueBg:      '#FFF7ED',   // era azul claro — agora laranja claro
  green:       '#166534',
  greenBg:     '#DCFCE7',
  greenBorder: '#86EFAC',
  white:       '#FFFFFF',
};

// ── Layout constants ──────────────────────────────────────────────────────────

const MARGIN    = 36;
const PAGE_W    = 595.28;
const PAGE_H    = 841.89;
const CONTENT_W = PAGE_W - MARGIN * 2;

// ── Drawing helpers ───────────────────────────────────────────────────────────

function fillRect(doc, x, y, w, h, color) {
  doc.fillColor(color).rect(x, y, w, h).fill();
}

function hline(doc, y, color = C.divider, lw = 0.5) {
  doc.strokeColor(color).lineWidth(lw)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
}

// ── Page Header ───────────────────────────────────────────────────────────────

function drawPageHeader(doc, logoPath) {
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

  const infoX = logoX + logoW + 12;
  const infoW = 220;
  const infoY = 13;

  doc.font('Helvetica-Bold').fontSize(8).fillColor(C.black)
     .text('VISUAL PREMIUM', infoX, infoY, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text('CNPJ: 20.000.300/0001-88   IE: 9066233666', infoX, infoY + 11, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text('RUA GENERAL RONDON, 745 – NOVA RUSSIA – PONTA GROSSA – PR', infoX, infoY + 21, { width: infoW });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text('Telefone: +55 (42) 3086-8600', infoX, infoY + 38, { width: infoW, lineBreak: false });

  const titleX = infoX + infoW + 10;
  const titleW = PAGE_W - MARGIN - titleX;

  doc.strokeColor(C.divider).lineWidth(0.8)
     .moveTo(titleX - 6, 10).lineTo(titleX - 6, H - 10).stroke();

  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.gray)
     .text('RELATÓRIO DE COMPRAS', titleX, 17, { width: titleW, align: 'right', lineBreak: false });

  doc.font('Helvetica-Bold').fontSize(9).fillColor(C.accent)
     .text('ORÇAMENTO DE MATERIAIS', titleX, 31, { width: titleW, align: 'right', lineBreak: false });

  doc.strokeColor(C.divider).lineWidth(1).moveTo(0, H).lineTo(PAGE_W, H).stroke();
}

// ── Section Header ────────────────────────────────────────────────────────────

function drawSectionHeader(doc, y, title) {
  const H = 20;
  fillRect(doc, MARGIN, y, CONTENT_W, H, C.bgHeader);
  fillRect(doc, MARGIN, y, 4, H, C.accent);
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.black)
     .text(title.toUpperCase(), MARGIN + 12, y + 7);
  return y + H;
}

// ── Bloco de resumo executivo ─────────────────────────────────────────────────

function drawResumoBox(doc, y, totalMateriais, totalFornecedores, totalSelecionado) {
  const boxH = 46;
  const colW = CONTENT_W / 3;

  fillRect(doc, MARGIN, y, CONTENT_W, boxH, C.bgHeader);
  fillRect(doc, MARGIN, y, 3, boxH, C.blue);

  doc.strokeColor(C.divider).lineWidth(0.5)
     .moveTo(MARGIN + colW,     y + 6).lineTo(MARGIN + colW,     y + boxH - 6).stroke();
  doc.strokeColor(C.divider).lineWidth(0.5)
     .moveTo(MARGIN + colW * 2, y + 6).lineTo(MARGIN + colW * 2, y + boxH - 6).stroke();

  const items = [
    { label: 'MATERIAIS NO ORÇAMENTO',  value: `${totalMateriais}`,            color: C.black },
    { label: 'FORNECEDORES ENVOLVIDOS', value: `${totalFornecedores}`,          color: C.black },
    { label: 'MELHOR TOTAL UNITÁRIO',   value: formatCurrency(totalSelecionado), color: C.green },
  ];

  items.forEach((item, i) => {
    const cx = MARGIN + colW * i;
    doc.font('Helvetica').fontSize(7).fillColor(C.gray)
       .text(item.label, cx + 10, y + 10, { width: colW - 16, align: 'center', lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(11).fillColor(item.color)
       .text(item.value, cx + 10, y + 22, { width: colW - 16, align: 'center', lineBreak: false });
  });

  return y + boxH;
}

// ── Header do card de material ────────────────────────────────────────────────

function drawMaterialHeader(doc, y, index, nome, unidade, totalForn, quantidade, modoOrcamento) {
  const H = 28;
  fillRect(doc, MARGIN, y, CONTENT_W, H, C.accent);

  fillRect(doc, MARGIN, y, 28, H, '#C44B00');
  doc.font('Helvetica-Bold').fontSize(9).fillColor(C.white)
     .text(`${index}`, MARGIN, y + (H - 9) / 2, { width: 28, align: 'center', lineBreak: false });

  doc.font('Helvetica-Bold').fontSize(9).fillColor(C.white)
     .text(nome, MARGIN + 34, y + 6, { lineBreak: false });

  const modoTexto = modoOrcamento === 'metroQuadrado' ? 'Orçado por m²' : (modoOrcamento ? 'Orçado por unidade' : null);
  const modoLabel = modoOrcamento === 'metroQuadrado' ? 'por m²' : (modoOrcamento ? 'por unidade' : null);

  const subtexto = [
    unidade    ? `Un: ${unidade}`                  : null,
    quantidade ? `Qtd: ${formatNumber(quantidade)}` : null,
  ].filter(Boolean).join('  ·  ');

  if (subtexto) {
    doc.font('Helvetica').fontSize(7).fillColor(C.white)
       .text(subtexto, MARGIN + 34, y + 18, { lineBreak: false });
  }

  // Modo orçamento badge no lado direito
  const rightParts = [];
  if (modoLabel) rightParts.push(modoLabel.toUpperCase());
  rightParts.push(`${totalForn} ${totalForn === 1 ? 'fornecedor' : 'fornecedores'}`);

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.white)
     .text(
       rightParts.join('  ·  '),
       MARGIN, y + (H - 7) / 2,
       { width: CONTENT_W - 6, align: 'right', lineBreak: false }
     );

  return y + H;
}

// ── Cabeçalho da tabela de fornecedores ──────────────────────────────────────

function drawFornecedorTableHeader(doc, y, cols) {
  const H = 18;
  fillRect(doc, MARGIN, y, CONTENT_W, H, C.bgHeader);

  doc.strokeColor('#D1D5DB').lineWidth(0.6)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  doc.strokeColor('#D1D5DB').lineWidth(0.6)
     .moveTo(MARGIN, y + H).lineTo(PAGE_W - MARGIN, y + H).stroke();

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.gray);
  for (const col of cols) {
    doc.text(col.label, col.x + col.pad, y + (H - 7) / 2,
      { width: col.w - col.pad * 2, align: col.hAlign, lineBreak: false });
  }

  doc.strokeColor(C.divider).lineWidth(0.4);
  for (let i = 1; i < cols.length; i++) {
    doc.moveTo(cols[i].x, y + 3).lineTo(cols[i].x, y + H - 3).stroke();
  }

  return y + H;
}

// ── Tabela de fornecedores de um item ─────────────────────────────────────────

function drawFornecedoresTable(doc, item, _ignoredMelhorFornId, startY) {
  const cols = [
    { key: 'fornecedor', label: 'FORNECEDOR',     w: 188, hAlign: 'left',   cAlign: 'left',   pad: 7 },
    { key: 'preco',      label: 'PREÇO UNIT.',    w: 95,  hAlign: 'right',  cAlign: 'right',  pad: 6 },
    { key: 'precoM2',    label: 'PREÇO M²',       w: 90,  hAlign: 'right',  cAlign: 'right',  pad: 6 },
    { key: 'total',      label: 'TOTAL (Qtd×Pr)', w: 110, hAlign: 'right',  cAlign: 'right',  pad: 6 },
    { key: 'status',     label: 'STATUS',          w: 40,  hAlign: 'center', cAlign: 'center', pad: 2 },
  ];

  let cx = MARGIN;
  for (const col of cols) { col.x = cx; cx += col.w; }

  const FONT_SZ = 7.5;
  let y = drawFornecedorTableHeader(doc, startY, cols);

  const precos   = item.precos ?? {};

  if (Object.keys(precos).length === 0) {
    fillRect(doc, MARGIN, y, CONTENT_W, 22, C.white);
    doc.font('Helvetica').fontSize(8).fillColor(C.lightGray)
       .text('Nenhum fornecedor vinculado a este material.', MARGIN, y + 7,
         { width: CONTENT_W, align: 'center', lineBreak: false });
    return y + 22;
  }

  const usarM2     = item.modoOrcamento === 'metroQuadrado';
  const quantidade = Number(item.quantidade) || 1;

  // Calcular menor preço unitário e menor preço m² independentemente
  let menorPrecoUnit = Infinity;
  let menorPrecoM2   = Infinity;
  for (const fData of Object.values(precos)) {
    if (fData.preco   != null && fData.preco   < menorPrecoUnit) menorPrecoUnit = fData.preco;
    if (fData.precoM2 != null && fData.precoM2 < menorPrecoM2)   menorPrecoM2  = fData.precoM2;
  }
  if (!isFinite(menorPrecoUnit)) menorPrecoUnit = null;
  if (!isFinite(menorPrecoM2))   menorPrecoM2   = null;

  // Ordenar priorizando melhor em ambos, depois pelo modo ativo
  const entradas = Object.entries(precos).sort(([, a], [, b]) => {
    const aMenorUnit = menorPrecoUnit != null && a.preco   != null && a.preco   === menorPrecoUnit;
    const aMenorM2   = menorPrecoM2   != null && a.precoM2 != null && a.precoM2 === menorPrecoM2;
    const bMenorUnit = menorPrecoUnit != null && b.preco   != null && b.preco   === menorPrecoUnit;
    const bMenorM2   = menorPrecoM2   != null && b.precoM2 != null && b.precoM2 === menorPrecoM2;
    const aAmbos = aMenorUnit && aMenorM2;
    const bAmbos = bMenorUnit && bMenorM2;
    if (aAmbos && !bAmbos) return -1;
    if (bAmbos && !aAmbos) return 1;
    const va = usarM2 ? (a.precoM2 ?? Infinity) : (a.preco ?? Infinity);
    const vb = usarM2 ? (b.precoM2 ?? Infinity) : (b.preco ?? Infinity);
    return va - vb;
  });

  const drawColDividers = (rowY, rowH) => {
    doc.strokeColor(C.divider).lineWidth(0.4);
    for (let i = 1; i < cols.length; i++) {
      doc.moveTo(cols[i].x, rowY + 3).lineTo(cols[i].x, rowY + rowH - 3).stroke();
    }
  };

  entradas.forEach(([fIdStr, fData], idx) => {
    const preco         = fData.preco   != null ? fData.preco   : null;
    const pm2           = fData.precoM2 != null ? fData.precoM2 : null;
    const valorEfetivo  = (usarM2 && pm2 != null) ? pm2 : preco;
    const totalLinha    = valorEfetivo != null ? formatCurrency(valorEfetivo * quantidade) : '—';

    // Destaque independente do modo
    const isMenorUnit = menorPrecoUnit != null && preco != null && preco === menorPrecoUnit;
    const isMenorM2   = menorPrecoM2   != null && pm2   != null && pm2   === menorPrecoM2;
    const isAnyMelhor = isMenorUnit || isMenorM2;

    const rowH = 26;
    // Linha sem fundo verde — apenas zebra normal
    const rowBg = idx % 2 === 1 ? C.bgRow : C.white;

    fillRect(doc, MARGIN, y, CONTENT_W, rowH, rowBg);

    const midY     = y + (rowH - FONT_SZ) / 2;
    const [C0, C1, C2, C3, C4] = cols;

    // Fornecedor: sempre neutro (sem negrito por ser melhor preço)
    doc.font('Helvetica')
       .fontSize(FONT_SZ).fillColor(C.black)
       .text(fData.fornecedorNome ?? '—', C0.x + C0.pad, midY,
         { width: C0.w - C0.pad * 2, align: 'left', lineBreak: false });

    // Preço unitário — verde se for o menor unitário
    doc.font(isMenorUnit ? 'Helvetica-Bold' : 'Helvetica')
       .fontSize(FONT_SZ).fillColor(isMenorUnit ? C.green : (preco != null ? C.black : C.lightGray))
       .text(preco != null ? formatCurrency(preco) : '—',
         C1.x + C1.pad, midY, { width: C1.w - C1.pad * 2, align: 'right', lineBreak: false });

    // Preço m² — verde se for o menor m²
    doc.font(isMenorM2 ? 'Helvetica-Bold' : 'Helvetica')
       .fontSize(FONT_SZ).fillColor(isMenorM2 ? C.green : (pm2 != null ? C.black : C.lightGray))
       .text(pm2 != null ? formatCurrency(pm2) : '—',
         C2.x + C2.pad, midY, { width: C2.w - C2.pad * 2, align: 'right', lineBreak: false });

    // Total pelo modo efetivo — verde se for o menor no modo ativo
    const isMelhorEfetivo = usarM2 ? isMenorM2 : isMenorUnit;
    doc.font(isMelhorEfetivo ? 'Helvetica-Bold' : 'Helvetica')
       .fontSize(FONT_SZ).fillColor(isMelhorEfetivo ? C.green : (valorEfetivo != null ? C.black : C.lightGray))
       .text(totalLinha, C3.x + C3.pad, midY,
         { width: C3.w - C3.pad * 2, align: 'right', lineBreak: false });

    // Status badge
    let statusText  = '—';
    let statusColor = C.lightGray;
    if      (isMenorUnit && isMenorM2) { statusText = 'Melhor ambos'; statusColor = C.green;     }
    else if (isMenorUnit)              { statusText = 'Menor unit.';  statusColor = C.green;     }
    else if (isMenorM2)                { statusText = 'Menor m²';    statusColor = C.green;     }
    else if (valorEfetivo == null)     { statusText = 'Sem preço';   statusColor = C.lightGray; }

    doc.font('Helvetica-Bold').fontSize(6).fillColor(statusColor)
       .text(statusText, C4.x + C4.pad, midY,
         { width: C4.w - C4.pad * 2, align: 'center', lineBreak: false });

    drawColDividers(y, rowH);
    y += rowH;
    doc.strokeColor(C.divider).lineWidth(0.4)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  });

  return y;
}

// ── Rodapé do card (modo + médias) ───────────────────────────────────────────

function drawCardFooter(doc, y, item) {
  const precos     = item.precos ?? {};
  const usarM2     = item.modoOrcamento === 'metroQuadrado';
  const quantidade = Number(item.quantidade) || 1;
  const entries    = Object.values(precos);

  // Calcular médias
  const precosUnit = entries.map(f => f.preco).filter(v => v != null);
  const precosM2   = entries.map(f => f.precoM2).filter(v => v != null);
  const mediaUnit  = precosUnit.length > 0 ? precosUnit.reduce((a, b) => a + b, 0) / precosUnit.length : null;
  const mediaM2    = precosM2.length   > 0 ? precosM2.reduce((a, b) => a + b, 0)   / precosM2.length   : null;

  if (mediaUnit == null && mediaM2 == null && !item.modoOrcamento) return y;

  const H = 22;
  fillRect(doc, MARGIN, y, CONTENT_W, H, C.accentBg);
  fillRect(doc, MARGIN, y, 3, H, C.accent);

  const midY = y + (H - 7) / 2;

  // Etiqueta do modo escolhido
  const modoLabel = usarM2 ? 'Orçado por: m²' : (item.modoOrcamento ? 'Orçado por: Unidade' : 'Modo não definido');
  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.accent)
     .text(modoLabel, MARGIN + 10, midY, { lineBreak: false });

  // Médias à direita
  const partes = [];
  if (mediaUnit != null) partes.push(`Média unit.: ${formatCurrency(mediaUnit)}`);
  if (mediaM2   != null) partes.push(`Média m²: ${formatCurrency(mediaM2)}`);

  if (partes.length > 0) {
    doc.font('Helvetica').fontSize(7).fillColor(C.gray)
       .text(partes.join('   ·   '), MARGIN, midY,
         { width: CONTENT_W - 12, align: 'right', lineBreak: false });
  }

  return y + H;
}

// ── Tabela de totais por fornecedor ───────────────────────────────────────────

function drawTotaisPorFornecedor(doc, y, itens) {
  const totaisMap = new Map();

  for (const item of itens) {
    const quantidade = Number(item.quantidade) || 1;

    for (const [fIdStr, fData] of Object.entries(item.precos ?? {})) {
      const fId = Number(fIdStr);

      if (!totaisMap.has(fId)) {
        totaisMap.set(fId, { nome: fData.fornecedorNome ?? `Fornecedor ${fId}`, totalUnit: 0, totalM2: 0, materiaisContados: 0 });
      }

      const entry = totaisMap.get(fId);
      entry.materiaisContados += 1;

      // Sempre acumula unitário e m² de forma independente
      if (fData.preco   != null) entry.totalUnit += fData.preco   * quantidade;
      if (fData.precoM2 != null) entry.totalM2   += fData.precoM2 * quantidade;
    }
  }

  if (totaisMap.size === 0) return y;

  // Ordena pelo menor total unitário (fornecedores sem unitário ficam no fim)
  const linhas = [...totaisMap.values()].sort((a, b) => {
    if (a.totalUnit === 0 && b.totalUnit === 0) return 0;
    if (a.totalUnit === 0) return 1;
    if (b.totalUnit === 0) return -1;
    return a.totalUnit - b.totalUnit;
  });

  const melhorUnit = linhas.find(l => l.totalUnit > 0)?.totalUnit ?? null;
  const melhorM2   = linhas.reduce((min, l) => l.totalM2 > 0 && (min == null || l.totalM2 < min) ? l.totalM2 : min, null);

  y = drawSectionHeader(doc, y, 'Totais por Fornecedor');
  y += 2;

  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(
       'Soma de todos os materiais por fornecedor — totais unitário e m² são independentes entre si.',
       MARGIN + 12, y + 2, { width: CONTENT_W - 20, lineBreak: false }
     );
  y += 14;

  const colForn = { x: MARGIN,            w: 210, pad: 8 };
  const colMats = { x: MARGIN + 210,      w: 80,  pad: 4 };
  const colUnit = { x: MARGIN + 290,      w: 115, pad: 6 };
  const colM2   = { x: MARGIN + 290 + 115, w: 118, pad: 6 };

  const TH_H = 18;
  fillRect(doc, MARGIN, y, CONTENT_W, TH_H, C.bgHeader);
  doc.strokeColor('#D1D5DB').lineWidth(0.6)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  doc.strokeColor('#D1D5DB').lineWidth(0.6)
     .moveTo(MARGIN, y + TH_H).lineTo(PAGE_W - MARGIN, y + TH_H).stroke();

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.gray);
  doc.text('FORNECEDOR',     colForn.x + colForn.pad, y + (TH_H - 7) / 2, { width: colForn.w - colForn.pad * 2, align: 'left',   lineBreak: false });
  doc.text('MATERIAIS',      colMats.x + colMats.pad, y + (TH_H - 7) / 2, { width: colMats.w - colMats.pad * 2, align: 'center', lineBreak: false });
  doc.text('TOTAL UNITÁRIO', colUnit.x + colUnit.pad, y + (TH_H - 7) / 2, { width: colUnit.w - colUnit.pad * 2, align: 'right',  lineBreak: false });
  doc.text('TOTAL M²',       colM2.x  + colM2.pad,   y + (TH_H - 7) / 2, { width: colM2.w  - colM2.pad  * 2,  align: 'right',  lineBreak: false });

  doc.strokeColor(C.divider).lineWidth(0.4);
  for (const col of [colMats, colUnit, colM2]) {
    doc.moveTo(col.x, y + 3).lineTo(col.x, y + TH_H - 3).stroke();
  }
  y += TH_H;

  const ROW_H = 24;
  linhas.forEach((linha, idx) => {
    const isMelhorUnit = melhorUnit != null && linha.totalUnit === melhorUnit && linha.totalUnit > 0;
    const isMelhorM2   = melhorM2   != null && linha.totalM2  === melhorM2   && linha.totalM2  > 0;

    // Linha sem fundo verde — apenas zebra normal
    const rowBg = idx % 2 === 1 ? C.bgRow : C.white;
    fillRect(doc, MARGIN, y, CONTENT_W, ROW_H, rowBg);

    const midY = y + (ROW_H - 7.5) / 2;

    // Nome do fornecedor: sempre cor/peso neutro, sem destaque
    doc.font('Helvetica')
       .fontSize(7.5).fillColor(C.black)
       .text(linha.nome, colForn.x + colForn.pad, midY,
         { width: colForn.w - colForn.pad * 2, align: 'left', lineBreak: false });

    doc.font('Helvetica').fontSize(7.5).fillColor(C.gray)
       .text(
         `${linha.materiaisContados} ${linha.materiaisContados === 1 ? 'mat.' : 'mats.'}`,
         colMats.x + colMats.pad, midY,
         { width: colMats.w - colMats.pad * 2, align: 'center', lineBreak: false }
       );

    // Destaca apenas o valor unitário menor
    doc.font(isMelhorUnit ? 'Helvetica-Bold' : 'Helvetica')
       .fontSize(8).fillColor(isMelhorUnit ? C.green : (linha.totalUnit > 0 ? C.black : C.lightGray))
       .text(linha.totalUnit > 0 ? formatCurrency(linha.totalUnit) : '—',
         colUnit.x + colUnit.pad, midY,
         { width: colUnit.w - colUnit.pad * 2, align: 'right', lineBreak: false });

    // Destaca apenas o valor m² menor
    doc.font(isMelhorM2 ? 'Helvetica-Bold' : 'Helvetica')
       .fontSize(8).fillColor(isMelhorM2 ? C.green : (linha.totalM2 > 0 ? C.black : C.lightGray))
       .text(linha.totalM2 > 0 ? formatCurrency(linha.totalM2) : '—',
         colM2.x + colM2.pad, midY,
         { width: colM2.w - colM2.pad * 2, align: 'right', lineBreak: false });

    doc.strokeColor(C.divider).lineWidth(0.4);
    for (const col of [colMats, colUnit, colM2]) {
      doc.moveTo(col.x, y + 3).lineTo(col.x, y + ROW_H - 3).stroke();
    }
    doc.strokeColor(C.divider).lineWidth(0.4)
       .moveTo(MARGIN, y + ROW_H).lineTo(PAGE_W - MARGIN, y + ROW_H).stroke();

    y += ROW_H;
  });

  doc.strokeColor(C.divider).lineWidth(0.8)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();

  return y;
}

// ── Rodapé de página ──────────────────────────────────────────────────────────

function drawFooter(doc, pageNum, totalPages) {
  const y = PAGE_H - 36;
  hline(doc, y - 8);
  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(
       `Gerado em ${formatDateTime(new Date())}   •   Visual Premium — Orçamento de Materiais`,
       MARGIN, y, { width: CONTENT_W - 60, align: 'left' }
     )
     .text(
       `Página ${pageNum}${totalPages ? ` de ${totalPages}` : ''}`,
       MARGIN, y, { width: CONTENT_W, align: 'right' }
     );
}

// ── Monta o nome completo do material com medida e espessura ─────────────────

function _nomeCompleto(item) {
  const partes = [item.materialNome ?? 'Material'];
  if (item.materialMedida)    partes.push(String(item.materialMedida).trim());
  if (item.materialEspessura) partes.push(String(item.materialEspessura).trim());
  return partes.join(' ');
}

// ── Exportação principal ──────────────────────────────────────────────────────

const orcamentoPdfService = {
  /**
   * Gera o PDF do orçamento a partir dos dados enviados pelo frontend.
   *
   * @param {Object} dados
   * @param {string} dados.titulo
   * @param {Array}  dados.itens  - cada item: { materialNome, materialUnidade, quantidade,
   *                                 modoOrcamento, fornecedorSelecionado,
   *                                 precos: { [fornecedorId]: { fornecedorNome, preco, precoM2 } } }
   */
  async gerarPdfDeItens(dados) {
    const { titulo, itens = [] } = dados;

    const logoPath = path.join(__dirname, '../../../frontend/assets/images/logoPreta.png');

    // Calcula o menor preço possível somando o menor unitário de cada item
    const totalMinimoUnit = itens.reduce((acc, item) => {
      const precos = item.precos ?? {};
      const quantidade = Number(item.quantidade) || 1;
      const menorPreco = Object.values(precos)
        .map(f => f.preco)
        .filter(v => v != null)
        .reduce((min, v) => (min == null || v < min) ? v : min, null);
      return acc + (menorPreco != null ? menorPreco * quantidade : 0);
    }, 0);

    const totalFornecedoresUnicos = new Set(
      itens.flatMap((item) => Object.keys(item.precos ?? {}).map(Number))
    ).size;

    return new Promise((resolve, reject) => {
      const doc    = new PDFDocument({ size: 'A4', margin: 0, bufferPages: true });
      const chunks = [];

      doc.on('data',  (chunk) => chunks.push(chunk));
      doc.on('end',   () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      drawPageHeader(doc, logoPath);
      let y = 90;

      // ── Título + data ──────────────────────────────────────────────────────
      fillRect(doc, MARGIN, y, CONTENT_W, 36, C.bgHeader);
      fillRect(doc, MARGIN, y, 4, 36, C.accent);

      doc.font('Helvetica').fontSize(8).fillColor(C.gray)
         .text('RELATÓRIO GERADO EM', MARGIN + 14, y + 7, { lineBreak: false });
      doc.font('Helvetica-Bold').fontSize(18).fillColor(C.black)
         .text(titulo || 'Orçamento', MARGIN + 14, y + 15, { lineBreak: false });

      doc.font('Helvetica').fontSize(7.5).fillColor(C.gray)
         .text('Data de Emissão', PAGE_W - MARGIN - 130, y + 7,
           { width: 130, align: 'right', lineBreak: false });
      doc.font('Helvetica-Bold').fontSize(9).fillColor(C.black)
         .text(formatDateTime(new Date()), PAGE_W - MARGIN - 130, y + 19,
           { width: 130, align: 'right', lineBreak: false });

      y += 36 + 10;

      // ── Resumo executivo ───────────────────────────────────────────────────
      y = drawResumoBox(doc, y, itens.length, totalFornecedoresUnicos, totalMinimoUnit);
      y += 14;

      // ── Totais por fornecedor ──────────────────────────────────────────────
      const estimTotaisH = 52 + totalFornecedoresUnicos * 26 + 20;
      if (y + estimTotaisH > PAGE_H - 60) {
        drawFooter(doc, doc.bufferedPageRange().count, null);
        doc.addPage();
        drawPageHeader(doc, logoPath);
        y = 90;
      }
      y = drawTotaisPorFornecedor(doc, y, itens);
      y += 14;

      hline(doc, y);
      y += 12;

      // ── Cards de materiais ─────────────────────────────────────────────────
      itens.forEach((item, i) => {
        const totalForn = Object.keys(item.precos ?? {}).length;
        const estimH    = 28 + 18 + Math.max(totalForn, 1) * 26 + 22 + 12;

        if (y + estimH > PAGE_H - 60) {
          drawFooter(doc, doc.bufferedPageRange().count, null);
          doc.addPage();
          drawPageHeader(doc, logoPath);
          y = 90;
        }

        y = drawMaterialHeader(
          doc, y, i + 1,
          _nomeCompleto(item),
          item.materialUnidade ?? null,
          totalForn,
          item.quantidade ?? 1,
          item.modoOrcamento ?? null
        );

        y = drawFornecedoresTable(doc, item, null, y);
        y = drawCardFooter(doc, y, item);

        doc.strokeColor(C.divider).lineWidth(0.8)
           .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();

        y += 12;
      });

      // ── Rodapé em todas as páginas ─────────────────────────────────────────
      const range = doc.bufferedPageRange();
      for (let i = 0; i < range.count; i++) {
        doc.switchToPage(range.start + i);
        drawFooter(doc, i + 1, range.count);
      }

      doc.end();
    });
  },
};

module.exports = orcamentoPdfService;