const PDFDocument = require('pdfkit');
const prisma      = require('../utils/prisma');
const path        = require('path');

function formatCurrency(value) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value ?? 0);
}

function formatCurrencyPreciso(value) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(value ?? 0);
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

const MAPA_CARACTERES_ESPECIAIS = {
  '\u2018': "'", '\u2019': "'", '\u201A': "'",
  '\u201C': '"', '\u201D': '"', '\u201E': '"',
  '\u2013': '-', '\u2014': '-', '\u2212': '-',
  '\u2022': '-', '\u25CF': '-', '\u25AA': '-', '\u25E6': '-',
  '\u2026': '...',
  '\u00A0': ' ', '\u2009': ' ', '\u200B': '',
  '\u2192': '->', '\u2190': '<-',
  '\u2705': '', '\u274C': '', '\u26A0': '',
};

function sanitizarTextoPdf(texto) {
  if (!texto) return texto;

  const textoNormalizado = texto.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  let resultado = '';
  for (const char of textoNormalizado) {
    const code = char.codePointAt(0);
    if (MAPA_CARACTERES_ESPECIAIS[char] !== undefined) {
      resultado += MAPA_CARACTERES_ESPECIAIS[char];
    } else if (code === 0x09) {
      resultado += ' ';
    } else if (code === 0x0A || (code >= 0x20 && code <= 0xFF)) {
      resultado += char;
    }
  }
  return resultado;
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

  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.gray)
     .text('ORDEM DE COMPRA', ocX, 14, { width: ocW, align: 'right', lineBreak: false });

  doc.font('Helvetica-Bold').fontSize(28).fillColor(C.black)
     .text(`#${oc.id}`, ocX, 22, { width: ocW, align: 'right', lineBreak: false });

  const st = statusLabel(oc.status);
  doc.font('Helvetica-Bold').fontSize(6.5).fillColor(st.color)
     .text(st.text, ocX, 56, { width: ocW, align: 'right', lineBreak: false });

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

function drawFornecedorDestaque(doc, y, nomeFornecedor) {
  const blockH = 30;
  const padH   = 14;

  fillRect(doc, MARGIN, y, CONTENT_W, blockH, C.bgHeader);
  fillRect(doc, MARGIN, y, 4, blockH, C.accent);

  doc.font('Helvetica-Bold').fontSize(7).fillColor(C.gray)
     .text('FORNECEDOR', MARGIN + padH, y + 6, { width: CONTENT_W - padH * 2, lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(13).fillColor(C.black)
     .text(nomeFornecedor || '—', MARGIN + padH, y + 15, { width: CONTENT_W - padH * 2, lineBreak: false });

  return y + blockH;
}

function drawAvisoNotaFiscal(doc, y) {
  const blockH = 62;
  const padH   = 16;
  const padV   = 12;

  fillRect(doc, MARGIN, y, CONTENT_W, blockH, '#FFF4EC');
  doc.rect(MARGIN, y, CONTENT_W, blockH).strokeColor(C.accent).lineWidth(1).stroke();
  fillRect(doc, MARGIN, y, 4, blockH, C.accent);

  const textX = MARGIN + padH;
  const textW = CONTENT_W - padH * 2;

  const titleY = y + padV;
  doc.fillColor(C.accent).circle(textX + 2.5, titleY + 5, 2.5).fill();
  doc.font('Helvetica-Bold').fontSize(9).fillColor(C.accent)
     .text('ATENÇÃO — ENVIO DA NOTA FISCAL', textX + 12, titleY, { width: textW - 12, lineBreak: false });

  const rowY   = titleY + 20;
  const colGap = 24;
  const colW   = (textW - colGap) / 2;
  const col2X  = textX + colW + colGap;

  doc.strokeColor('#F0C9A8').lineWidth(0.8)
     .moveTo(textX + colW + colGap / 2, rowY - 2)
     .lineTo(textX + colW + colGap / 2, rowY + 24)
     .stroke();

  doc.font('Helvetica').fontSize(7.5).fillColor(C.gray)
     .text('E-MAIL PARA NOTA FISCAL', textX, rowY, { width: colW, lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(10.5).fillColor(C.black)
     .text('financeiro@visualpremium.com.br', textX, rowY + 12, { width: colW, lineBreak: false });

  doc.font('Helvetica').fontSize(7.5).fillColor(C.gray)
     .text('WHATSAPP PARA NOTA FISCAL', col2X, rowY, { width: colW, lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(10.5).fillColor(C.black)
     .text('(42) 9 9830-0088', col2X, rowY + 12, { width: colW, lineBreak: false });

  return y + blockH;
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
  const itensComQtdUnidade  = itens.filter(i => !i.usarM2 && i.qtdUnidade != null && Number(i.qtdUnidade) > 0);
  const temQtdUnidadeGlobal = itensComQtdUnidade.length > 0;

  const labelQtdPorUnid = 'QTD/UNIDADE';

  const cols = [
    { key: 'material',   label: 'MATERIAL',      w: temQtdUnidadeGlobal ? 120 : 190, hAlign: 'left',   cAlign: 'left',   pad: 5 },
    { key: 'qtd',        label: 'QTD',           w: 55,                 hAlign: 'center', cAlign: 'center', pad: 3 },
    ...(temQtdUnidadeGlobal ? [{ key: 'qtdPorUnid', label: labelQtdPorUnid, w: 70, hAlign: 'center', cAlign: 'center', pad: 3 }] : []),
    { key: 'unidade',    label: 'UNIDADE',       w: 44,                 hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'preco',      label: 'PREÇO',         w: 110,                hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'precoTotal', label: 'VALOR TOTAL (R$)', w: 88,             hAlign: 'center', cAlign: 'center', pad: 5 },
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

    doc.fillColor(C.gray);
    for (const col of cols) {
      const availW = col.w - col.pad * 2;
      let hSz = 7;
      doc.font('Helvetica-Bold').fontSize(hSz);
      while (hSz > 5 && doc.widthOfString(col.label) > availW) {
        hSz -= 0.5;
        doc.fontSize(hSz);
      }
      doc.text(col.label, col.x + col.pad, y + (HEADER_H - hSz) / 2,
               { width: availW, align: col.hAlign, lineBreak: false });
    }
    drawColDividers(y, HEADER_H);
    y += HEADER_H;
  };

  drawHeader();

  itens.forEach((item, idx) => {
    const nome    = sanitizarTextoPdf(item.material?.nome ?? (item.descricaoItem?.trim() || '(material excluído)'));
    const unidade = (item.material?.unidade ?? '—').toLowerCase();
    const descricao = item.descricaoItem?.trim() ? sanitizarTextoPdf(item.descricaoItem.trim()) : null;

    const qtdUnidadeNum = item.qtdUnidade != null ? Number(item.qtdUnidade) : null;
    const temQtdUnidade  = !item.usarM2 && qtdUnidadeNum != null && qtdUnidadeNum > 0;

    const temMedida = item.material?.medida && item.material.medida.trim().length > 0;

    let dimensao = null;
    if (!temMedida) {
      const comp = item.material?.comprimento;
      const larg = item.material?.largura;
      
      if (comp && larg) {
        dimensao = `${comp}X${larg}M`;
      } else if (comp) {
        dimensao = `${comp}M`;
      } else if (larg) {
        dimensao = `${larg}M`;
      }
    }

    const espessuraFmt = item.material?.espessura
      ? `${String(item.material.espessura).replace(/\s*mm\s*$/i, '').trim()}mm`
      : null;

    const especParts = [
      temMedida ? `${item.material.medida}` : dimensao,
      espessuraFmt,
      item.material?.identificador ? `${item.material.identificador}`  : null,
    ].filter(Boolean);
    const especLine = especParts.length > 0 ? especParts.join('  •  ') : null;

    doc.font('Helvetica-Bold').fontSize(FONT_SZ);
    const matH  = doc.heightOfString(nome, { width: cols[0].w - cols[0].pad * 2 });
    const especH = especLine
      ? doc.font('Helvetica').fontSize(FONT_SZ - 1).heightOfString(especLine, { width: cols[0].w - cols[0].pad * 2 }) + 2
      : 0;
    const descH = descricao
      ? doc.font('Helvetica').fontSize(FONT_SZ - 0.5).heightOfString(descricao, { width: cols[0].w - cols[0].pad * 2 }) + 3
      : 0;
    const rowH  = Math.max(20, matH + especH + descH + ROW_PAD_V * 2);

    if (y + rowH > PAGE_H - FOOTER_RESERVE) {
      drawFooter(doc, doc.bufferedPageRange().count);
      doc.addPage();
      y = MARGIN;
      drawHeader();
    }

    if (idx % 2 === 0) fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgRow);

    const tySingle = y + (rowH - FONT_SZ) / 2;
    const tyMulti  = y + ROW_PAD_V;

    const C0 = cols.find(c => c.key === 'material');
    const C1 = cols.find(c => c.key === 'qtd');
    const Cqu = cols.find(c => c.key === 'qtdPorUnid');
    const C2 = cols.find(c => c.key === 'unidade');
    const C3 = cols.find(c => c.key === 'preco');
    const C5 = cols.find(c => c.key === 'precoTotal');

    doc.save();
    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(nome, C0.x + C0.pad, tyMulti, { width: C0.w - C0.pad * 2, align: 'left', lineBreak: true });
    let nextLineY = tyMulti + matH;
    if (especLine) {
      doc.font('Helvetica').fontSize(FONT_SZ - 1).fillColor(C.gray)
         .text(especLine, C0.x + C0.pad, nextLineY, { width: C0.w - C0.pad * 2, align: 'left', lineBreak: true });
      nextLineY += especH;
    }
    if (descricao) {
      doc.font('Helvetica').fontSize(FONT_SZ - 0.5).fillColor(C.gray)
         .text(descricao, C0.x + C0.pad, nextLineY + 1, { width: C0.w - C0.pad * 2, align: 'left', lineBreak: true });
    }
    doc.restore();

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.black)
       .text(formatNumber(item.quantidade), C1.x + C1.pad, tySingle,
             { width: C1.w - C1.pad * 2, align: 'center', lineBreak: false });

    if (Cqu) {
      doc.font('Helvetica').fontSize(FONT_SZ).fillColor(temQtdUnidade ? C.black : C.lightGray)
         .text(temQtdUnidade ? formatNumber(qtdUnidadeNum) : '—', Cqu.x + Cqu.pad, tySingle,
               { width: Cqu.w - Cqu.pad * 2, align: 'center', lineBreak: false });
    }

    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.black)
       .text(unidade, C2.x + C2.pad, tySingle,
             { width: C2.w - C2.pad * 2, align: 'center', lineBreak: false });

    if (C3) {
      let precoTexto = '—';
      if (item.usarM2) {
        if (item.precoMetroQuadrado != null) {
          precoTexto = `${formatCurrencyPreciso(item.precoMetroQuadrado)} / m²`;
        }
      } else {
        const unidadeSufixo = (item.material?.unidade ?? '').trim().toLowerCase();
        precoTexto = unidadeSufixo
          ? `${formatCurrencyPreciso(item.precoUnitario)} / ${unidadeSufixo}`
          : formatCurrencyPreciso(item.precoUnitario);
      }
      doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
         .text(precoTexto, C3.x + C3.pad, tySingle,
               { width: C3.w - C3.pad * 2, align: 'center', lineBreak: false });
    }

    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(formatCurrency(item.precoTotal), C5.x + C5.pad, tySingle,
             { width: C5.w - C5.pad * 2, align: 'center', lineBreak: false });

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
  const padV    = 7;
  const padH    = 8;

  const textW = maxW - padH * 2;

  doc.font('Helvetica').fontSize(7);

  const textoFormatado = sanitizarTextoPdf(observacoes)
    .split('\n')
    .filter(Boolean)
    .map(linha => `• ${linha}`)
    .join('\n');

  const textoH = doc.heightOfString(textoFormatado, {
    width: textW,
    lineGap: 2,
  });

  const tituloH = 12;
  const blockH  = padV + tituloH + textoH + padV;
  const blockY  = footerY - blockH - 6;

  fillRect(doc, MARGIN, blockY, maxW, blockH, C.bgHeader);
  fillRect(doc, MARGIN, blockY, 3, blockH, C.accent);

  doc.font('Helvetica-Bold')
     .fontSize(7)
     .fillColor(C.black)
     .text('Observações', MARGIN + padH, blockY + padV);

  doc.font('Helvetica')
     .fontSize(7)
     .fillColor(C.black)
     .text(
       textoFormatado,
       MARGIN + padH,
       blockY + padV + tituloH,
       {
         width: textW,
         lineGap: 2,
       }
     );
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
     .text('INDISPENSÁVEL', blockX + padH, blockY + padV, { width: blockW - padH * 2, lineBreak: false });

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
     .text(`Gerado em ${formatDate(new Date())}   •   ${empresaNome}`,
           MARGIN, y, { width: CONTENT_W - 60, align: 'left' })
     .text(`Página ${pageNum}`, MARGIN, y, { width: CONTENT_W, align: 'right' });
}

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

      drawPageHeader(doc, oc, logoPath);
      let y = 90;

      drawSectionHeader(doc, y, 'Informações da Ordem de Compra');
      y += 26;

      const nomeFornecedor = oc.fornecedor?.nomeFantasia ?? oc.fornecedor?.nome ?? '—';
      y = drawFornecedorDestaque(doc, y, nomeFornecedor);
      y += 10;

      const infoRows = [
        ['Nº da OC',            `#${oc.id}`],
        ['Status',              statusLabel(oc.status).text],
        ['Data',                formatDate(oc.data)],
        ['Requisitante',        oc.requisitante || '—'],
        ['Forma de Pagamento',  oc.formaPagamento || '—'],
        ['Prazo de Pagamento',  oc.prazoPagamento || '—'],
      ];

      for (const [label, value] of infoRows) {
        drawInfoRow(doc, y, label, value);
        y += 14;
      }

      y += 10;
      y = drawAvisoNotaFiscal(doc, y);

      y += 10;
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

module.exports = ordemCompraPdfService;