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

// ─── Gerador de PDF de Orçamento — Layout Matricial (espelha o editor Flutter) ─

/**
 * Monta a lista ordenada de todos os IDs de fornecedores presentes nos itens.
 * Retorna array de { fornecedorId, fornecedorNome }.
 */
function coletarFornecedores(itens) {
  const map = new Map(); // id -> nome
  itens.forEach((item) => {
    Object.entries(item.precos ?? {}).forEach(([fId, pf]) => {
      if (!map.has(fId)) map.set(fId, pf.fornecedorNome ?? `Fornecedor ${fId}`);
    });
  });
  return Array.from(map.entries()).map(([id, nome]) => ({ id, nome }));
}

/**
 * Para cada item, obtém o preço efetivo de um fornecedor (unitário ou m²).
 */
function precoEfetivo(pf, usarM2) {
  if (!pf) return null;
  if (usarM2) return pf.precoM2 ?? pf.preco ?? null;
  return pf.preco ?? null;
}

/**
 * Remove do payload os preços de fornecedores ocultos, caso o chamador
 * informe `dados.fornecedoresOcultos` (array de ids). O app Flutter já envia
 * os itens sem esses preços, mas este filtro fica como segunda camada de
 * proteção para qualquer outro client que delegue o filtro ao servidor —
 * um fornecedor oculto nunca deve aparecer no PDF nem entrar nos totais.
 */
function aplicarFornecedoresOcultos(itens, fornecedoresOcultos) {
  if (!Array.isArray(fornecedoresOcultos) || fornecedoresOcultos.length === 0) return itens;
  const ocultos = new Set(fornecedoresOcultos.map(String));
  return itens.map((item) => {
    const precosFiltrados = Object.fromEntries(
      Object.entries(item.precos ?? {}).filter(([fId]) => !ocultos.has(String(fId)))
    );
    const fornecedorSelecionado = ocultos.has(String(item.fornecedorSelecionado))
      ? null
      : item.fornecedorSelecionado;
    return { ...item, precos: precosFiltrados, fornecedorSelecionado };
  });
}

/**
 * Desenha a tabela matricial do orçamento (materiais × fornecedores).
 * Orientação landscape: gira para A4 wide quando há muitos fornecedores.
 */
async function gerarPdfDeItens(dados) {
  const { titulo = 'Orçamento', fornecedoresOcultos = [] } = dados;
  const itens = aplicarFornecedoresOcultos(dados.itens ?? [], fornecedoresOcultos);

  return new Promise((resolve, reject) => {
    // Decidir orientação: landscape se > 3 fornecedores para ter espaço
    const fornecedores = coletarFornecedores(itens);
    const useLandscape = fornecedores.length > 3;

    const pageSize   = useLandscape ? [841.89, 595.28] : [595.28, 841.89];
    const pW         = pageSize[0];
    const pH         = pageSize[1];
    const margin     = 36;
    const contentW   = pW - margin * 2;

    const doc    = new PDFDocument({ size: pageSize, margin: 0, bufferPages: true });
    const chunks = [];

    doc.on('data',  (chunk) => chunks.push(chunk));
    doc.on('end',   () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const logoPath = path.join(__dirname, '../../../frontend/assets/images/logoPreta.png');
    const orcFake  = { _isOrdemCompra: false, logoEmpresa: 'PREMIUM', empresa: 'VISUAL PREMIUM' };

    // ── helpers locais que respeitam as dimensões da página ─────────────
    const fillR = (x, y, w, h, color) => doc.fillColor(color).rect(x, y, w, h).fill();
    const hlineL = (y, color = C.divider, lw = 0.5) => {
      doc.strokeColor(color).lineWidth(lw)
         .moveTo(margin, y).lineTo(pW - margin, y).stroke();
    };

    // ── Cabeçalho da página (versão simplificada para landscape) ────────
    const drawHeader = () => {
      const H = 70;
      fillR(0, 0, pW, H, C.white);
      fillR(0, 0, pW, 4, C.accent);

      const logoW = 90;
      try {
        doc.image(logoPath, margin, 14, { height: 38, fit: [logoW, 38] });
      } catch (_) {
        doc.font('Helvetica-Bold').fontSize(13).fillColor(C.accent)
           .text('Visual Premium', margin, 22, { lineBreak: false });
      }

      // Título do orçamento
      doc.font('Helvetica-Bold').fontSize(13).fillColor(C.accent)
         .text('ORÇAMENTO', margin + logoW + 12, 20, { width: contentW - logoW - 12, align: 'right', lineBreak: false });
      doc.font('Helvetica').fontSize(7.5).fillColor(C.lightGray)
         .text(`${titulo}   •   Emitido em ${formatDate(new Date())}`,
               margin + logoW + 12, 38, { width: contentW - logoW - 12, align: 'right', lineBreak: false });

      doc.strokeColor(C.divider).lineWidth(1)
         .moveTo(0, H).lineTo(pW, H).stroke();
      return H + 8;
    };

    const drawFooterL = (pageNum) => {
      const y = pH - 30;
      hlineL(y - 6);
      doc.font('Helvetica').fontSize(6.5).fillColor(C.lightGray)
         .text(`Gerado em ${formatDate(new Date())}   •   Visual Premium Estoque e Compras`,
               margin, y, { width: contentW - 60, align: 'left' })
         .text(`Página ${pageNum}`, margin, y, { width: contentW, align: 'right' });
    };

    // ── Cálculos matriciais ──────────────────────────────────────────────
    const totalMateriais = itens.length;

    // Para cada item, qual modo usar
    const usarM2PorItem = itens.map((item) => item.modoOrcamento === 'metroQuadrado');

    // Para cada fornecedor: total acumulado e cobertura
    const totaisForn    = {}; // id -> { total, comPreco, vinculados }
    const menorPorItem  = []; // menor preço por item (menor entre fornecedores)

    fornecedores.forEach(({ id }) => {
      totaisForn[id] = { total: 0, comPreco: 0, vinculados: 0 };
    });

    itens.forEach((item, iIdx) => {
      const qtd    = item.quantidade ?? 1;
      const usM2   = usarM2PorItem[iIdx];
      let   menor  = null;

      fornecedores.forEach(({ id }) => {
        const pf = (item.precos ?? {})[id];
        if (!pf) return;
        totaisForn[id].vinculados += 1;
        const p = precoEfetivo(pf, usM2);
        if (p != null) {
          totaisForn[id].total    += p * qtd;
          totaisForn[id].comPreco += 1;
          if (menor === null || p < menor) menor = p;
        }
      });

      menorPorItem.push(menor);
    });

    // Ordena fornecedores pelo total ascendente, zeros por último —
    // espelha exatamente o sort do Flutter em _buildTabelaMatriz:
    //   if (ta == 0 && tb == 0) return 0;
    //   if (ta == 0) return 1;   // zero vai pro fim
    //   if (tb == 0) return -1;
    //   return ta.compareTo(tb); // ascendente
    fornecedores.sort((a, b) => {
      const ta = totaisForn[a.id]?.total ?? 0;
      const tb = totaisForn[b.id]?.total ?? 0;
      if (ta === 0 && tb === 0) return 0;
      if (ta === 0) return 1;
      if (tb === 0) return -1;
      return ta - tb;
    });

    // Total da coluna "Melhor Preço" (soma dos menores por item)
    let totalMelhorPreco  = 0;
    let matComMelhorPreco = 0;
    itens.forEach((item, i) => {
      const m = menorPorItem[i];
      if (m != null) {
        totalMelhorPreco  += m * (item.quantidade ?? 1);
        matComMelhorPreco += 1;
      }
    });

    // Fornecedor com menor total (para destaque de coluna)
    const fornComPreco = fornecedores.filter(({ id }) => totaisForn[id].total > 0);
    const menorTotalForn = fornComPreco.length > 0
      ? Math.min(...fornComPreco.map(({ id }) => totaisForn[id].total))
      : null;

    // Sugestão: fornecedor com maior cobertura e menor total
    let maxCob        = 0;
    let suggFornId    = null;
    let suggFornNome  = null;
    let suggTotal     = null;
    fornecedores.forEach(({ id, nome }) => {
      const cob = totaisForn[id].vinculados;
      const tot = totaisForn[id].total;
      if (cob > maxCob || (cob === maxCob && tot > 0 && (suggTotal === null || tot < suggTotal))) {
        maxCob       = cob;
        suggFornId   = id;
        suggFornNome = nome;
        suggTotal    = tot;
      }
    });

    // ── Layout de colunas ────────────────────────────────────────────────
    // Colunas fixas: Material | Qtd | ...Fornecedores... | Melhor Preço
    // Escala automaticamente para acomodar qualquer número de fornecedores
    const nForn      = fornecedores.length;
    const FOOTER_RES = 100;

    // Largura ideal por fornecedor quando há espaço sobrando
    const FORN_IDEAL = 85;

    // Calcula quanto espaço é necessário com as proporções padrão
    // e reduz as colunas fixas proporcionalmente se necessário
    const calcLayout = () => {
      // Largura mínima absoluta da coluna Melhor Preço — nunca eliminada
      const MELHOR_MIN = 60;
      // Largura mínima por coluna de fornecedor antes de comprimir fixas
      const FORN_ABS   = 50;

      // Passo 1: tamanhos ideais
      let mat    = 170;
      let qtd    = 48;
      let melhor = 80;
      let forn   = nForn > 0 ? (contentW - mat - qtd - melhor) / nForn : FORN_IDEAL;

      // Cap superior: não deixar fornecedor ficar largo demais
      if (forn >= FORN_IDEAL) forn = FORN_IDEAL;

      // Passo 2: comprime colunas fixas moderadamente (mat→110, qtd→36, melhor→70)
      if (forn < FORN_ABS) {
        mat    = 110;
        qtd    = 36;
        melhor = 70;
        forn   = nForn > 0 ? (contentW - mat - qtd - melhor) / nForn : FORN_IDEAL;
      }

      // Passo 3: comprime mais agressivamente (mat→88, qtd→28, melhor→MELHOR_MIN)
      if (forn < FORN_ABS) {
        mat    = 88;
        qtd    = 28;
        melhor = MELHOR_MIN;
        forn   = nForn > 0 ? (contentW - mat - qtd - melhor) / nForn : FORN_IDEAL;
      }

      // Passo 4: aceita forn menor que FORN_ABS — divide o que sobra igualmente
      // (coluna Melhor jamais é zerada; apenas forn encolhe mais)
      if (forn < FORN_ABS) {
        forn = Math.max(38, (contentW - mat - qtd - melhor) / nForn);
      }

      return { COL_MAT: mat, COL_QTD: qtd, COL_MELHOR: melhor, COL_FORN: forn };
    };

    const { COL_MAT, COL_QTD, COL_MELHOR, COL_FORN } = calcLayout();

    // Fator de escala para fontes (1.0 em tamanho normal, <1 quando comprimido)
    const fontScale  = Math.min(1, COL_FORN / FORN_IDEAL);
    const fornFontSz = Math.max(5, Math.round(6.5 * fontScale * 10) / 10);

    // x inicial de cada coluna
    const xMat    = margin;
    const xQtd    = xMat + COL_MAT;
    const xForn   = (i) => xQtd + COL_QTD + i * COL_FORN;
    const xMelhor = xQtd + COL_QTD + nForn * COL_FORN;

    const ROW_H      = 42;
    const HDR_H      = 30;
    const TOTAL_H    = 26;
    const SUGEST_H   = 28;
    const FONT_SZ    = 7;

    // ── Função: cabeçalho da tabela ──────────────────────────────────────
    const drawTableHeader = (y) => {
      fillR(margin, y, contentW, HDR_H, '#F1F3F5');
      hlineL(y, '#D1D5DB', 0.8);

      const ty = y + (HDR_H - 7) / 2;

      // Material
      doc.font('Helvetica-Bold').fontSize(6.5).fillColor(C.gray)
         .text('MATERIAL', xMat + 4, ty, { width: COL_MAT - 8, lineBreak: false });

      // Qtd
      doc.font('Helvetica-Bold').fontSize(6.5).fillColor(C.gray)
         .text('QTD', xQtd + 2, ty, { width: COL_QTD - 4, align: 'center', lineBreak: false });

      // Fornecedores
      fornecedores.forEach(({ id, nome }, fi) => {
        const x        = xForn(fi);
        const isMenuor = menorTotalForn != null && totaisForn[id].total === menorTotalForn && totaisForn[id].total > 0;
        const cob      = totaisForn[id].vinculados;

        if (isMenuor) {
          fillR(x + 2, y + 2, COL_FORN - 4, HDR_H - 4, '#D1FAE5');
          doc.rect(x + 2, y + 2, COL_FORN - 4, HDR_H - 4)
             .strokeColor('#6EE7B7').lineWidth(0.4).stroke();
        }

        if (isMenuor) {
          doc.font('Helvetica-Bold').fontSize(5).fillColor(C.statusOk)
             .text('▼ MENOR TOTAL', x + 4, y + 5, { width: COL_FORN - 8, align: 'center', lineBreak: false });
        }

        doc.font('Helvetica-Bold').fontSize(isMenuor ? Math.min(7, fornFontSz + 0.5) : fornFontSz)
           .fillColor(isMenuor ? C.statusOk : C.gray)
           .text(nome, x + 4, isMenuor ? y + 13 : ty - 3, { width: COL_FORN - 8, align: 'center', lineBreak: false });

        doc.font('Helvetica').fontSize(Math.max(4.5, fornFontSz - 1)).fillColor(C.lightGray)
           .text(`${cob}/${totalMateriais} mat.`, x + 4, isMenuor ? y + 21 : ty + 8,
                 { width: COL_FORN - 8, align: 'center', lineBreak: false });

        // Divisor vertical
        if (fi > 0) {
          doc.strokeColor(C.divider).lineWidth(0.4)
             .moveTo(x, y + 4).lineTo(x, y + HDR_H - 4).stroke();
        }
      });

      // Coluna Melhor Preço
      doc.font('Helvetica-Bold').fontSize(6).fillColor('#1D4ED8')
         .text('★ MELHOR', xMelhor + 4, ty - 4, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });
      doc.font('Helvetica').fontSize(5.5).fillColor('#93C5FD')
         .text('menor por item', xMelhor + 4, ty + 5, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });

      doc.strokeColor(C.divider).lineWidth(0.4)
         .moveTo(xMelhor, y + 4).lineTo(xMelhor, y + HDR_H - 4).stroke();

      hlineL(y + HDR_H, '#D1D5DB', 0.8);
      return y + HDR_H;
    };

    // ── Função: linha de totais ──────────────────────────────────────────
    const drawTotalsRow = (y) => {
      fillR(margin, y, contentW, TOTAL_H, '#F8F9FA');
      hlineL(y, '#D1D5DB', 1);

      const ty = y + (TOTAL_H - 7) / 2;

      doc.font('Helvetica-Bold').fontSize(7).fillColor(C.black)
         .text('TOTAL POR FORNECEDOR', xMat + 4, ty, { width: COL_MAT + COL_QTD - 8, lineBreak: false });

      fornecedores.forEach(({ id }, fi) => {
        const x      = xForn(fi);
        const info   = totaisForn[id];
        const isMen  = menorTotalForn != null && info.total === menorTotalForn && info.total > 0;
        const semPrc = info.vinculados - info.comPreco;

        doc.font('Helvetica-Bold').fontSize(isMen ? Math.min(8, fornFontSz + 1) : fornFontSz)
           .fillColor(isMen ? C.statusOk : (info.total > 0 ? C.black : C.lightGray))
           .text(info.total > 0 ? formatCurrency(info.total) : '—',
                 x + 4, semPrc > 0 ? ty - 3 : ty, { width: COL_FORN - 8, align: 'center', lineBreak: false });

        if (semPrc > 0) {
          doc.font('Helvetica').fontSize(Math.max(4.5, fornFontSz - 1)).fillColor(C.statusWarn)
             .text(`${semPrc} sem preço`, x + 4, ty + 7, { width: COL_FORN - 8, align: 'center', lineBreak: false });
        }
      });

      // Melhor total acumulado
      fillR(xMelhor + 2, y + 3, COL_MELHOR - 4, TOTAL_H - 6, '#EFF6FF');
      doc.rect(xMelhor + 2, y + 3, COL_MELHOR - 4, TOTAL_H - 6)
         .strokeColor('#BFDBFE').lineWidth(0.5).stroke();
      doc.font('Helvetica-Bold').fontSize(7.5).fillColor('#1D4ED8')
         .text(matComMelhorPreco > 0 ? formatCurrency(totalMelhorPreco) : '—',
               xMelhor + 4, ty - 2, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });
      doc.font('Helvetica').fontSize(5.5).fillColor('#93C5FD')
         .text(`${matComMelhorPreco}/${totalMateriais} mat.`,
               xMelhor + 4, ty + 7, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });

      hlineL(y + TOTAL_H, '#D1D5DB', 1);
      return y + TOTAL_H;
    };

    // ── Função: bloco de sugestão de compra ideal ────────────────────────
    const drawSugestao = (y) => {
      if (!suggFornId || matComMelhorPreco === 0) return y;

      const diferenca = (suggTotal ?? 0) - totalMelhorPreco;
      const isMelhor  = diferenca <= 0;

      const bgColor  = isMelhor ? '#F0FDF4' : '#FFFBEB';
      const bdColor  = isMelhor ? '#86EFAC' : '#FCD34D';
      const txColor  = isMelhor ? C.statusOk : C.statusWarn;
      const icon     = isMelhor ? '✓' : '⚠';

      fillR(margin, y, contentW, SUGEST_H, bgColor);
      fillR(margin, y, 4, SUGEST_H, isMelhor ? C.statusOk : C.statusWarn);
      hlineL(y, bdColor, 1);

      const ty = y + (SUGEST_H - 7) / 2;

      doc.font('Helvetica-Bold').fontSize(7).fillColor(txColor)
         .text(`${icon} SUGESTÃO DE COMPRA IDEAL`, margin + 10, ty - 4, { lineBreak: false });

      let msg;
      if (isMelhor) {
        msg = `"${suggFornNome}" cobre mais materiais e já é o mais vantajoso com ${formatCurrency(suggTotal ?? 0)} — mesmo comprando tudo de um único fornecedor.`;
      } else {
        const dif = formatCurrency(Math.abs(diferenca));
        msg = `Comprando tudo de "${suggFornNome}" (${formatCurrency(suggTotal ?? 0)}) vs melhor por item separado (${formatCurrency(totalMelhorPreco)}): diferença de ${dif} a mais. Avalie se a praticidade compensa.`;
      }

      doc.font('Helvetica').fontSize(6.5).fillColor(txColor)
         .text(msg, margin + 10, ty + 5, { width: contentW - 20, lineBreak: false });

      hlineL(y + SUGEST_H, bdColor, 0.5);
      return y + SUGEST_H;
    };

    // ═══════════════════════════════════════════════════════════════════
    // INÍCIO DO DOCUMENTO
    // ═══════════════════════════════════════════════════════════════════

    let y = drawHeader();

    if (itens.length === 0) {
      doc.font('Helvetica').fontSize(10).fillColor(C.gray)
         .text('Nenhum item neste orçamento.', margin, y + 20, { width: contentW, align: 'center' });
    } else {
      // Seção: título da tabela matricial
      drawSectionHeader(doc, y, `Comparativo de Preços — ${totalMateriais} ${totalMateriais === 1 ? 'material' : 'materiais'} × ${nForn} ${nForn === 1 ? 'fornecedor' : 'fornecedores'}`);
      y += 26;

      // Cabeçalho da tabela
      y = drawTableHeader(y);

      // ── Linhas de materiais ────────────────────────────────────────────
      itens.forEach((item, iIdx) => {
        const qtd  = item.quantidade ?? 1;
        const usM2 = usarM2PorItem[iIdx];
        const menor = menorPorItem[iIdx];

        // Mede altura necessária para o nome (pode quebrar linha)
        doc.font('Helvetica-Bold').fontSize(FONT_SZ);
        const nomeH = doc.heightOfString(item.materialNome, { width: COL_MAT - 8 });
        const descH = item.descricao?.trim()
          ? doc.font('Helvetica').fontSize(5.5).heightOfString(item.descricao.trim(), { width: COL_MAT - 8 }) + 2
          : 0;
        const rowH  = Math.max(ROW_H, nomeH + descH + 14);

        // Quebra de página
        if (y + rowH > pH - FOOTER_RES) {
          drawFooterL(doc.bufferedPageRange().count);
          doc.addPage();
          y = drawHeader();
          y = drawTableHeader(y);
        }

        // Fundo alternado
        if (iIdx % 2 === 0) fillR(margin, y, contentW, rowH, C.bgRow);

        const tyCtr = y + (rowH - FONT_SZ) / 2;
        const tyTop = y + 8;

        // ── Coluna Material ────────────────────────────────────────────
        doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
           .text(item.materialNome, xMat + 4, tyTop, { width: COL_MAT - 8, lineBreak: true });

        const subparts = [item.materialCategoria, item.materialMedida, item.materialEspessura, item.materialIdentificador]
          .filter(Boolean).join(' · ');
        if (subparts) {
          doc.font('Helvetica').fontSize(5.5).fillColor(C.lightGray)
             .text(subparts, xMat + 4, tyTop + nomeH + 1, { width: COL_MAT - 8, lineBreak: false });
        }
        if (item.descricao?.trim()) {
          doc.font('Helvetica').fontSize(5.5).fillColor(C.gray)
             .text(item.descricao.trim(), xMat + 4, tyTop + nomeH + (subparts ? 7 : 1), { width: COL_MAT - 8, lineBreak: false });
        }

        // ── Coluna Qtd ─────────────────────────────────────────────────
        const unidLabel = usM2 ? 'm²' : (item.materialUnidade || '');
        doc.font('Helvetica').fontSize(6.5).fillColor(C.black)
           .text(formatNumberSmart(qtd), xQtd + 2, tyCtr - 4, { width: COL_QTD - 4, align: 'center', lineBreak: false });
        if (unidLabel) {
          doc.font('Helvetica').fontSize(5.5).fillColor(C.lightGray)
             .text(unidLabel, xQtd + 2, tyCtr + 4, { width: COL_QTD - 4, align: 'center', lineBreak: false });
        }

        // ── Colunas de fornecedores ────────────────────────────────────
        fornecedores.forEach(({ id }, fi) => {
          const x      = xForn(fi);
          const pf     = (item.precos ?? {})[id];

          // Divisor vertical
          doc.strokeColor(C.divider).lineWidth(0.3)
             .moveTo(x, y + 4).lineTo(x, y + rowH - 4).stroke();

          if (!pf) {
            // Fornecedor não vinculado
            doc.font('Helvetica').fontSize(5.5).fillColor(C.lightGray)
               .text('—', x + 4, tyCtr, { width: COL_FORN - 8, align: 'center', lineBreak: false });
            return;
          }

          const preco  = precoEfetivo(pf, usM2);
          const total  = preco != null ? preco * qtd : null;
          const isMen  = menor != null && preco != null && preco === menor;

          // Destaque fundo verde suave para o menor da linha
          if (isMen) {
            fillR(x + 2, y + 2, COL_FORN - 4, rowH - 4, '#F0FDF4');
            doc.rect(x + 2, y + 2, COL_FORN - 4, rowH - 4)
               .strokeColor('#86EFAC').lineWidth(0.4).stroke();
          }

          if (preco != null) {
            // Seta para baixo + preço
            if (isMen) {
              doc.font('Helvetica-Bold').fontSize(Math.max(4.5, fornFontSz - 1)).fillColor(C.statusOk)
                 .text('▼ MENOR', x + 4, y + 5, { width: COL_FORN - 8, align: 'center', lineBreak: false });
            }
            const precoY = isMen ? y + 12 : tyCtr - 4;
            doc.font(isMen ? 'Helvetica-Bold' : 'Helvetica')
               .fontSize(isMen ? Math.min(8, fornFontSz + 1) : fornFontSz)
               .fillColor(isMen ? C.statusOk : C.black)
               .text(formatCurrency(preco), x + 4, precoY, { width: COL_FORN - 8, align: 'center', lineBreak: false });

            // Total da linha
            if (total != null) {
              doc.font('Helvetica').fontSize(Math.max(4.5, fornFontSz - 1))
                 .fillColor(isMen ? '#15803D' : C.gray)
                 .text(formatCurrency(total), x + 4, precoY + 9, { width: COL_FORN - 8, align: 'center', lineBreak: false });
            }

            // Observação de disponibilidade
            if (pf.observacao) {
              const obsY = precoY + 18;
              doc.font('Helvetica').fontSize(Math.max(4, fornFontSz - 1.5))
                 .fillColor(C.statusWarn)
                 .text(pf.observacao, x + 4, obsY, { width: COL_FORN - 8, align: 'center', lineBreak: false });
            }
          } else {
            doc.font('Helvetica').fontSize(Math.max(4.5, fornFontSz - 0.5)).fillColor(C.lightGray)
               .text('sem preço', x + 4, tyCtr - 4, { width: COL_FORN - 8, align: 'center', lineBreak: false });

            // Observação mesmo sem preço
            if (pf.observacao) {
              doc.font('Helvetica').fontSize(Math.max(4, fornFontSz - 1.5))
                 .fillColor(C.statusWarn)
                 .text(pf.observacao, x + 4, tyCtr + 5, { width: COL_FORN - 8, align: 'center', lineBreak: false });
            }
          }
        });

        // ── Coluna Melhor Preço ────────────────────────────────────────
        doc.strokeColor('#BFDBFE').lineWidth(0.3)
           .moveTo(xMelhor, y + 4).lineTo(xMelhor, y + rowH - 4).stroke();

        if (menor != null) {
          const melhorTotal = menor * qtd;
          fillR(xMelhor + 2, y + 3, COL_MELHOR - 4, rowH - 6, '#EFF6FF');
          doc.rect(xMelhor + 2, y + 3, COL_MELHOR - 4, rowH - 6)
             .strokeColor('#BFDBFE').lineWidth(0.4).stroke();

          doc.font('Helvetica-Bold').fontSize(7.5).fillColor('#1D4ED8')
             .text(formatCurrency(menor), xMelhor + 4, tyCtr - 5, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });
          doc.font('Helvetica').fontSize(6).fillColor('#60A5FA')
             .text(formatCurrency(melhorTotal), xMelhor + 4, tyCtr + 4, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });
        } else {
          doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
             .text('—', xMelhor + 4, tyCtr, { width: COL_MELHOR - 8, align: 'center', lineBreak: false });
        }

        hlineL(y + rowH, C.divider, 0.3);
        y += rowH;
      });

      // ── Linha de totais ────────────────────────────────────────────────
      if (y + TOTAL_H + SUGEST_H > pH - FOOTER_RES) {
        drawFooterL(doc.bufferedPageRange().count);
        doc.addPage();
        y = drawHeader();
      }
      y = drawTotalsRow(y);
      y = drawSugestao(y);

      y += 12;
    }

    // Rodapé em todas as páginas
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(range.start + i);
      drawFooterL(i + 1);
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