const PDFDocument  = require('pdfkit');
const prisma       = require('../utils/prisma');
const path         = require('path');

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
  statusLim: '#2563EB',
};

const MARGIN    = 30;
const PAGE_W    = 841.89;
const PAGE_H    = 595.28;
const CONTENT_W = PAGE_W - MARGIN * 2;

function fillRect(doc, x, y, w, h, color) {
  doc.fillColor(color).rect(x, y, w, h).fill();
}

function hline(doc, y, color = C.divider, lw = 0.5) {
  doc.strokeColor(color).lineWidth(lw)
     .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
}

function statusLabel(status) {
  switch (status) {
    case 'OK':      return { text: 'OK',      color: C.statusOk,  bg: '#DCFCE7' };
    case 'LIMITE':  return { text: 'LIMITE',  color: C.statusWarn, bg: '#FEF3C7' };
    case 'CRITICO': return { text: 'CRÍTICO', color: C.statusErr, bg: '#FEE2E2' };
    case 'INATIVO': return { text: 'INATIVO', color: C.lightGray, bg: '#F3F4F6' };
    default:        return { text: status,    color: C.gray,      bg: '#F3F4F6' };
  }
}

function drawPageHeader(doc, categoria, status, logoPath) {
  const H = 70;

  fillRect(doc, 0, 0, PAGE_W, H, C.white);
  fillRect(doc, 0, 0, PAGE_W, 4, C.accent);

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

  const empresa = {
    nome:     'VISUAL PREMIUM',
    cnpjIe:   'CNPJ: 20.000.300/0001-88   IE: 9066233666',
    endereco: 'RUA GENERAL RONDON, 745 – NOVA RUSSIA – PONTA GROSSA – PR',
    telefone: 'Telefone: +55 (42) 3086-8600',
  };

  const infoX = logoX + logoW + 12;
  const infoW = 240;
  const infoY = 13;

  doc.font('Helvetica-Bold').fontSize(8).fillColor(C.black)
     .text(empresa.nome, infoX, infoY, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.cnpjIe, infoX, infoY + 11, { width: infoW, lineBreak: false });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.endereco, infoX, infoY + 21, { width: infoW, lineBreak: true });
  doc.font('Helvetica').fontSize(7).fillColor(C.gray)
     .text(empresa.telefone, infoX, infoY + 38, { width: infoW, lineBreak: false });

  const titleX = infoX + infoW + 12;
  const titleW = PAGE_W - MARGIN - titleX;

  doc.strokeColor(C.divider).lineWidth(0.8)
     .moveTo(titleX - 6, 10).lineTo(titleX - 6, H - 10).stroke();

  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.gray)
     .text('RELATÓRIO DE ESTOQUE', titleX, 14, { width: titleW, align: 'right', lineBreak: false });

  const catLabel    = categoria && categoria !== 'TODAS' ? categoria : 'TODOS OS MATERIAIS';
  const statusSufx  = (status && status !== 'TODOS') ? ` · ${status.toUpperCase()}` : '';
  const label = `${catLabel}${statusSufx}`;
  doc.font('Helvetica-Bold').fontSize(11).fillColor(C.black)
     .text(label, titleX, 28, { width: titleW, align: 'right', lineBreak: false });

  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(`Gerado em ${formatDate(new Date())}`, titleX, 50, { width: titleW, align: 'right', lineBreak: false });

  doc.strokeColor(C.divider).lineWidth(1)
     .moveTo(0, H).lineTo(PAGE_W, H).stroke();
}

function drawSectionHeader(doc, y, title) {
  fillRect(doc, MARGIN, y, CONTENT_W, 20, C.bgHeader);
  fillRect(doc, MARGIN, y, 4, 20, C.accent);
  doc.font('Helvetica-Bold').fontSize(7.5).fillColor(C.black)
     .text(title.toUpperCase(), MARGIN + 12, y + 7);
}

function drawSummaryBox(doc, y, totais) {
  const boxH = 44;
  const colW = CONTENT_W / 4;

  fillRect(doc, MARGIN, y, CONTENT_W, boxH, C.bgHeader);

  const items = [
    { label: 'TOTAL DE MATERIAIS', value: String(totais.total),   color: C.black },
    { label: 'STATUS OK',          value: String(totais.ok),      color: C.statusOk },
    { label: 'LIMITE',             value: String(totais.limite),  color: C.statusLim },
    { label: 'CRÍTICO',            value: String(totais.critico), color: C.statusErr },
  ];

  items.forEach((item, i) => {
    const x = MARGIN + colW * i;
    if (i > 0) {
      doc.strokeColor(C.divider).lineWidth(0.5)
         .moveTo(x, y + 8).lineTo(x, y + boxH - 8).stroke();
    }
    doc.font('Helvetica').fontSize(6.5).fillColor(C.gray)
       .text(item.label, x + 8, y + 8, { width: colW - 16, align: 'center', lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(16).fillColor(item.color)
       .text(item.value, x + 8, y + 18, { width: colW - 16, align: 'center', lineBreak: false });
  });

  return y + boxH;
}

function drawMateriaisTable(doc, materiais, startY) {
  const cols = [
    { key: 'id',            label: 'ID',              w: 32,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'identificador', label: 'IDENTIFICADOR',   w: 52,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'nome',          label: 'MATERIAL',        w: 120, hAlign: 'left',   cAlign: 'left',   pad: 4 },
    { key: 'unidade',       label: 'UNIDADE',         w: 42,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'medida',        label: 'MEDIDA',          w: 52,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'espessura',     label: 'ESPESSURA',       w: 52,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'comprimento',   label: 'COMPRIMENTO',     w: 62,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'largura',       label: 'LARGURA',         w: 56,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'estMin',        label: 'EST. MÍN.',       w: 46,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'qtd',           label: 'QUANTIDADE',      w: 56,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'custoUltimo',   label: 'CUSTO ÚLT.',      w: 60,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'custoM2Ultimo', label: 'CUSTO M² ÚLT.',   w: 62,  hAlign: 'center', cAlign: 'center', pad: 3 },
    { key: 'status',        label: 'STATUS',          w: 51,  hAlign: 'center', cAlign: 'center', pad: 3 },
  ];

  const totalW = cols.reduce((s, c) => s + c.w, 0);
  const diff = CONTENT_W - totalW;
  cols[1].w += diff;

  let cx = MARGIN;
  for (const col of cols) { col.x = cx; cx += col.w; }

  const HEADER_H       = 22;
  const ROW_PAD_V      = 5;
  const FONT_SZ        = 6.5;
  const FOOTER_RESERVE = 50;

  let y = startY;

  const drawColDividers = (rowY, rowH) => {
    doc.strokeColor('#E0E0E0').lineWidth(0.3);
    for (let i = 1; i < cols.length; i++) {
      doc.moveTo(cols[i].x, rowY + 2).lineTo(cols[i].x, rowY + rowH - 2).stroke();
    }
  };

  const drawHeader = () => {
    fillRect(doc, MARGIN, y, CONTENT_W, HEADER_H, C.bgHeader);
    doc.strokeColor('#D1D5DB').lineWidth(0.8)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
    doc.strokeColor('#D1D5DB').lineWidth(0.8)
       .moveTo(MARGIN, y + HEADER_H).lineTo(PAGE_W - MARGIN, y + HEADER_H).stroke();

    doc.font('Helvetica-Bold').fontSize(6).fillColor(C.gray);
    for (const col of cols) {
      doc.text(col.label, col.x + col.pad, y + (HEADER_H - 7) / 2,
               { width: col.w - col.pad * 2, align: col.hAlign, lineBreak: false });
    }
    drawColDividers(y, HEADER_H);
    y += HEADER_H;
  };

  drawHeader();

  materiais.forEach((mat, idx) => {
    const nomeBase = mat.nome || '—';
    const matH = doc.heightOfString(nomeBase, { width: cols[1].w - cols[1].pad * 2, fontSize: FONT_SZ });
    const rowH = Math.max(18, matH + ROW_PAD_V * 2);

    if (y + rowH > PAGE_H - FOOTER_RESERVE) {
      doc.addPage();
      y = MARGIN;
      drawHeader();
    }

    if (idx % 2 === 0) fillRect(doc, MARGIN, y, CONTENT_W, rowH, C.bgRow);

    const tySingle = y + (rowH - FONT_SZ) / 2;
    const tyMulti  = y + ROW_PAD_V;

    const get = (col) => ({ x: col.x + col.pad, w: col.w - col.pad * 2 });

    const c0 = get(cols[0]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.lightGray)
       .text(String(mat.id), c0.x, tySingle, { width: c0.w, align: 'center', lineBreak: false });

    const c1 = get(cols[1]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.identificador || '—', c1.x, tySingle, { width: c1.w, align: 'center', lineBreak: false });

    const c2 = get(cols[2]);
    doc.font('Helvetica-Bold').fontSize(FONT_SZ).fillColor(C.black)
       .text(nomeBase, c2.x, tyMulti, { width: c2.w, align: 'left', lineBreak: true });

    const c3 = get(cols[3]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.black)
       .text(mat.unidade || '—', c3.x, tySingle, { width: c3.w, align: 'center', lineBreak: false });

    const c4 = get(cols[4]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.medida || '—', c4.x, tySingle, { width: c4.w, align: 'center', lineBreak: false });

    const c5 = get(cols[5]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.espessura || '—', c5.x, tySingle, { width: c5.w, align: 'center', lineBreak: false });

    const c6 = get(cols[6]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.comprimento != null ? formatNumber(mat.comprimento) : '—',
             c6.x, tySingle, { width: c6.w, align: 'center', lineBreak: false });

    const c7 = get(cols[7]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.largura != null ? formatNumber(mat.largura) : '—',
             c7.x, tySingle, { width: c7.w, align: 'center', lineBreak: false });

    const c8 = get(cols[8]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(formatNumber(mat.estoqueMinimo), c8.x, tySingle, { width: c8.w, align: 'center', lineBreak: false });

    const c9 = get(cols[9]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(formatNumber(mat.quantidade), c9.x, tySingle, { width: c9.w, align: 'center', lineBreak: false });

    const c10 = get(cols[10]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.custoUltimaCompra != null ? formatCurrency(mat.custoUltimaCompra) : '—',
             c10.x, tySingle, { width: c10.w, align: 'center', lineBreak: false });

    const c11 = get(cols[11]);
    doc.font('Helvetica').fontSize(FONT_SZ).fillColor(C.gray)
       .text(mat.custoM2UltimaCompra != null ? formatCurrency(mat.custoM2UltimaCompra) : '—',
             c11.x, tySingle, { width: c11.w, align: 'center', lineBreak: false });

    const c12 = get(cols[12]);
    const st = statusLabel(mat.status);
    const badgeH = 12;
    const badgeY = tySingle - 1;
    const badgePadX = 3;
    fillRect(doc, cols[12].x + badgePadX, badgeY, cols[12].w - badgePadX * 2, badgeH, st.bg);
    doc.font('Helvetica-Bold').fontSize(5.5).fillColor(st.color)
       .text(st.text, c12.x + 2, badgeY + 3, { width: c12.w - 4, align: 'center', lineBreak: false });

    drawColDividers(y, rowH);
    y += rowH;

    doc.strokeColor(C.divider).lineWidth(0.3)
       .moveTo(MARGIN, y).lineTo(PAGE_W - MARGIN, y).stroke();
  });

  return y;
}

function drawFooter(doc, pageNum, pageTotal) {
  const y = PAGE_H - 30;
  hline(doc, y - 8);
  doc.font('Helvetica').fontSize(7).fillColor(C.lightGray)
     .text(`Gerado em ${formatDate(new Date())}   •   Visual Premium Estoque e Compras`,
           MARGIN, y, { width: CONTENT_W - 60, align: 'left' })
     .text(`Página ${pageNum} de ${pageTotal}`, MARGIN, y, { width: CONTENT_W, align: 'right' });
}

const estoquePdfService = {
  async gerarPdf(categoria, status = 'TODOS', { busca, id, identificador, medida, espessura } = {}) {
    const where = { ativo: true };
    if (categoria && categoria !== 'TODAS') {
      where.categoria = { equals: categoria, mode: 'insensitive' };
    }
    const statusValidos = ['OK', 'LIMITE', 'CRITICO'];
    if (status && status !== 'TODOS' && statusValidos.includes(status.toUpperCase())) {
      where.status = status.toUpperCase();
    }
    if (busca)        where.nome          = { contains: busca, mode: 'insensitive' };
    if (id)           where.id            = Number(id);
    if (identificador) where.identificador = { contains: identificador, mode: 'insensitive' };
    if (medida)       where.medida        = { contains: medida, mode: 'insensitive' };
    if (espessura)    where.espessura     = { contains: espessura, mode: 'insensitive' };

    const materiais = await prisma.material.findMany({
      where,
      include: {
        fornecedorMateriais: {
          where: { ativo: true },
          select: { preco: true, precoMetroQuadrado: true },
        },
        historicoPrecos: {
          orderBy: { criadoEm: 'desc' },
          take: 1,
          select: { precoUnitario: true, precoM2: true },
        },
      },
      orderBy: [{ categoria: 'asc' }, { nome: 'asc' }],
    });

    const mediana = (arr) => {
      if (!arr.length) return null;
      const mid = Math.floor(arr.length / 2);
      return arr.length % 2 !== 0 ? arr[mid] : (arr[mid - 1] + arr[mid]) / 2;
    };

    const materiaisEnriquecidos = materiais.map((m) => {
      const precos = m.fornecedorMateriais
        .map((fm) => Number(fm.preco))
        .filter((p) => p > 0)
        .sort((a, b) => a - b);

      const precosM2 = m.fornecedorMateriais
        .map((fm) => Number(fm.precoMetroQuadrado))
        .filter((p) => p > 0)
        .sort((a, b) => a - b);

      const ultimoHistorico = m.historicoPrecos?.[0] ?? null;

      return {
        ...m,
        precoMediano:        mediana(precos),
        precoM2Mediano:      mediana(precosM2),
        custoUltimaCompra:   ultimoHistorico?.precoUnitario ? Number(ultimoHistorico.precoUnitario) : null,
        custoM2UltimaCompra: ultimoHistorico?.precoM2       ? Number(ultimoHistorico.precoM2)       : null,
      };
    });

    const totais = {
      total:   materiaisEnriquecidos.length,
      ok:      materiaisEnriquecidos.filter((m) => m.status === 'OK').length,
      limite:  materiaisEnriquecidos.filter((m) => m.status === 'LIMITE').length,
      critico: materiaisEnriquecidos.filter((m) => m.status === 'CRITICO').length,
    };

    const logoPath = path.join(__dirname, '../../../frontend/assets/images/logoPreta.png');

    const statusLabel2 = (status && status !== 'TODOS') ? ` — ${status.toUpperCase()}` : '';
    const filtrosExtras = [
      busca         && `Busca: "${busca}"`,
      id            && `ID: ${id}`,
      identificador && `Ident.: "${identificador}"`,
      medida        && `Medida: ${medida}`,
      espessura     && `Esp.: ${espessura}`,
    ].filter(Boolean).join(' · ');
    const filtrosSufx = filtrosExtras ? ` · ${filtrosExtras}` : '';
    const label = categoria && categoria !== 'TODAS'
      ? `Materiais — ${categoria}${statusLabel2}${filtrosSufx} (${materiaisEnriquecidos.length})`
      : `Todos os Materiais${statusLabel2}${filtrosSufx} (${materiaisEnriquecidos.length})`;

    function gerarDocumento(totalPaginas) {
      return new Promise((resolve, reject) => {
        const doc    = new PDFDocument({ size: 'A4', layout: 'landscape', margin: 0 });
        const chunks = [];
        let   pageNum = 1;

        doc.on('data',  (chunk) => chunks.push(chunk));
        doc.on('end',   () => resolve(Buffer.concat(chunks)));
        doc.on('error', reject);

        doc.on('pageAdded', () => {
        });

        const desenharConteudo = () => {
          drawPageHeader(doc, categoria, status, logoPath);
          let y = 84;

          drawSectionHeader(doc, y, 'Resumo do Estoque'); y += 24;
          y = drawSummaryBox(doc, y, totais);             y += 14;
          drawSectionHeader(doc, y, label);               y += 24;

          if (materiaisEnriquecidos.length === 0) {
            doc.font('Helvetica').fontSize(9).fillColor(C.gray)
               .text('Nenhum material encontrado.', MARGIN, y, { width: CONTENT_W, align: 'center' });
          } else {
            drawMateriaisTable(doc, materiaisEnriquecidos, y);
          }
        };

        if (totalPaginas === null) {
          doc.on('pageAdded', () => pageNum++);
          desenharConteudo();
          doc.end();
        } else {
          const origAddPage = doc.addPage.bind(doc);
          doc.addPage = (...args) => {
            drawFooter(doc, pageNum, totalPaginas);
            pageNum++;
            return origAddPage(...args);
          };

          desenharConteudo();
          drawFooter(doc, pageNum, totalPaginas);
          doc.end();
        }
      });
    }

    const bufCount = [];
    const totalPaginas = await new Promise((resolve, reject) => {
      const d = new PDFDocument({ size: 'A4', layout: 'landscape', margin: 0 });
      let count = 1;
      d.on('data',      () => {});
      d.on('pageAdded', () => count++);
      d.on('end',       () => resolve(count));
      d.on('error',     reject);

      drawPageHeader(d, categoria, status, logoPath);
      let y2 = 84;
      drawSectionHeader(d, y2, 'Resumo do Estoque'); y2 += 24;
      y2 = drawSummaryBox(d, y2, totais);             y2 += 14;
      drawSectionHeader(d, y2, label);               y2 += 24;
      if (materiaisEnriquecidos.length === 0) {
        d.font('Helvetica').fontSize(9).fillColor(C.gray)
         .text('Nenhum material encontrado.', MARGIN, y2, { width: CONTENT_W, align: 'center' });
      } else {
        drawMateriaisTable(d, materiaisEnriquecidos, y2);
      }
      d.end();
    });

    return gerarDocumento(totalPaginas);
  },
};

module.exports = estoquePdfService;