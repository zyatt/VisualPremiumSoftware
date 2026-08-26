const prisma = require('../utils/prisma');

function normalizarTelefone(tel) {
  if (!tel) return null;
  const digits = tel.replace(/\D/g, '');
  if (digits.length !== 10) {
    throw { status: 400, message: `Telefone inválido: use DDD (2 dígitos) + número (8 dígitos), ex: 4233091000` };
  }
  return digits;
}

// ---------------------------------------------------------------------
// Verificação de nome duplicado / semelhante entre fornecedores.
// Mesmo princípio usado no cadastro de materiais (estoque): normaliza o
// texto (maiúsculas, sem acento, espaços colapsados) para comparação
// exata, e usa distância de Levenshtein para detectar nomes parecidos
// (erros de digitação, abreviações, etc).
// ---------------------------------------------------------------------

function _normalizarTextoComparacao(v) {
  if (!v) return '';
  return v
    .trim()
    .toUpperCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ');
}

function _levenshtein(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  let anterior = Array.from({ length: b.length + 1 }, (_, j) => j);
  let atual = new Array(b.length + 1).fill(0);

  for (let i = 1; i <= a.length; i++) {
    atual[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const custo = a[i - 1] === b[j - 1] ? 0 : 1;
      atual[j] = Math.min(
        anterior[j] + 1,      // remoção
        atual[j - 1] + 1,     // inserção
        anterior[j - 1] + custo, // substituição
      );
    }
    [anterior, atual] = [atual, anterior];
  }
  return anterior[b.length];
}

function _similaridadeTexto(a, b) {
  if (a === '' && b === '') return 1;
  if (a === '' || b === '') return 0;
  const distancia = _levenshtein(a, b);
  const maiorTamanho = Math.max(a.length, b.length);
  return 1 - distancia / maiorTamanho;
}

function _similaridadePalavras(a, b) {
  const palavrasA = a.split(/\s+/).filter(Boolean);
  const palavrasB = b.split(/\s+/).filter(Boolean);
  if (palavrasA.length === 0 && palavrasB.length === 0) return 1;
  if (palavrasA.length === 0 || palavrasB.length === 0) return 0;

  const menor = palavrasA.length <= palavrasB.length ? palavrasA : palavrasB;
  const maior = palavrasA.length <= palavrasB.length ? palavrasB : palavrasA;
  const usados = new Array(maior.length).fill(false);

  let pesoCasado = 0;
  for (const palavra of menor) {
    let melhorIdx = -1;
    let melhorScore = 0;
    for (let i = 0; i < maior.length; i++) {
      if (usados[i]) continue;
      if (palavra === maior[i]) {
        melhorIdx = i;
        melhorScore = 1;
        break;
      }
      const tamMin = Math.min(palavra.length, maior[i].length);
      if (tamMin <= 2 && palavra !== maior[i]) continue;
      const score = _similaridadeTexto(palavra, maior[i]);
      if (score >= 0.75 && score > melhorScore) {
        melhorScore = score;
        melhorIdx = i;
      }
    }
    if (melhorIdx !== -1) {
      usados[melhorIdx] = true;
      pesoCasado += melhorScore * palavra.length;
    }
  }

  const pesoTotal = [...palavrasA, ...palavrasB].reduce((soma, p) => soma + p.length, 0);
  if (pesoTotal === 0) return 0;
  return (pesoCasado * 2) / pesoTotal;
}

/**
 * Retorna a lista de fornecedores ativos considerados iguais ou
 * semelhantes ao nome fantasia informado, ordenados por relevância
 * (exatos primeiro, depois por similaridade decrescente).
 *
 * @param {string} nomeFantasia texto digitado pelo usuário
 * @param {number|null} ignorarId id do fornecedor a excluir da busca
 *   (usado ao editar, para não comparar o registro com ele mesmo)
 */
async function _buscarSemelhantes(nomeFantasia, ignorarId = null) {
  const nomeNorm = _normalizarTextoComparacao(nomeFantasia);
  if (nomeNorm.length < 3) return [];

  const candidatos = await prisma.fornecedor.findMany({
    where: {
      ativo: true,
      ...(ignorarId ? { id: { not: ignorarId } } : {}),
    },
    select: {
      id: true,
      nomeFantasia: true,
      tipoFornecedor: true,
      nomeVendedor: true,
      cnpj: true,
    },
  });

  const encontrados = [];
  for (const f of candidatos) {
    const fNomeNorm = _normalizarTextoComparacao(f.nomeFantasia);

    const exata = fNomeNorm === nomeNorm;

    const similaridadeNome = _similaridadeTexto(nomeNorm, fNomeNorm);
    const similaridadePalavras = _similaridadePalavras(nomeNorm, fNomeNorm);
    const similaridadeEfetiva = Math.max(similaridadeNome, similaridadePalavras);

    const curto = nomeNorm.length <= fNomeNorm.length ? nomeNorm : fNomeNorm;
    const longo = nomeNorm.length <= fNomeNorm.length ? fNomeNorm : nomeNorm;
    const contido = curto.length >= 4 && curto !== '' && longo.includes(curto);

    const palavrasDigitadas = new Set(nomeNorm.split(/\s+/).filter((t) => t.length >= 2));
    const palavrasCadastro = new Set(fNomeNorm.split(/\s+/).filter((t) => t.length >= 2));
    const palavrasComuns = [...palavrasDigitadas].filter((p) => palavrasCadastro.has(p)).length;
    const menorQtdPalavras = Math.min(palavrasDigitadas.size, palavrasCadastro.size);
    const cobreParcialPalavras =
      palavrasComuns >= 2 && menorQtdPalavras > 0 && palavrasComuns / menorQtdPalavras >= 0.6;

    const similar =
      !exata &&
      (similaridadeNome >= 0.72 ||
        similaridadePalavras >= 0.72 ||
        contido ||
        cobreParcialPalavras);

    if (exata || similar) {
      encontrados.push({
        id: f.id,
        nomeFantasia: f.nomeFantasia,
        tipoFornecedor: f.tipoFornecedor,
        nomeVendedor: f.nomeVendedor,
        cnpj: f.cnpj,
        exata,
        similaridade: similaridadeEfetiva,
        contido,
      });
    }
  }

  encontrados.sort((a, b) => {
    if (a.exata !== b.exata) return a.exata ? -1 : 1;
    if (a.contido !== b.contido) return a.contido ? -1 : 1;
    return b.similaridade - a.similaridade;
  });

  return encontrados.slice(0, 5);
}

/**
 * Endpoint de apoio ao formulário: retorna fornecedores parecidos
 * enquanto o usuário digita, sem bloquear nada (aviso, não erro).
 */
async function verificarSemelhantes(nomeFantasia, ignorarId) {
  return _buscarSemelhantes(nomeFantasia, ignorarId ? Number(ignorarId) : null);
}

async function listar(busca, tipo, id) {
  const where = { ativo: true };

  if (busca) {
    where.OR = [
      { nomeFantasia: { contains: busca, mode: 'insensitive' } },
      { nomeVendedor: { contains: busca, mode: 'insensitive' } },
      { cnpj:         { contains: busca, mode: 'insensitive' } },
    ];
  }

  if (tipo) {
    where.tipoFornecedor = tipo;
  }

  if (id) {
    where.id = Number(id);
  }

  return prisma.fornecedor.findMany({
    where,
    include: {
      materiais: {
        where: { ativo: true },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

function _montarWhereFornecedor(busca, tipo, id) {
  const where = { ativo: true };

  if (busca) {
    where.OR = [
      { nomeFantasia: { contains: busca, mode: 'insensitive' } },
      { nomeVendedor: { contains: busca, mode: 'insensitive' } },
      { cnpj:         { contains: busca, mode: 'insensitive' } },
    ];
  }

  if (tipo) {
    where.tipoFornecedor = tipo;
  }

  if (id) {
    where.id = Number(id);
  }

  return where;
}

async function listarPaginado(filtros = {}) {
  const { busca, tipo, id, pagina = 1, porPagina = 40 } = filtros;
  const where = _montarWhereFornecedor(busca, tipo, id);

  const take = Number(porPagina) || 40;
  const skip = (Number(pagina) - 1) * take;

  const total = await prisma.fornecedor.count({ where });

  const fornecedores = await prisma.fornecedor.findMany({
    where,
    include: {
      materiais: {
        where: { ativo: true },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
    take,
    skip,
  });

  return { data: fornecedores, total };
}

async function buscarParaVinculo(busca, limite = 50) {
  const where = { ativo: true };

  if (busca && busca.trim()) {
    where.OR = [
      { nomeFantasia: { contains: busca.trim(), mode: 'insensitive' } },
      { nomeVendedor: { contains: busca.trim(), mode: 'insensitive' } },
    ];
  }

  return prisma.fornecedor.findMany({
    where,
    select: {
      id:             true,
      nomeFantasia:   true,
      tipoFornecedor: true,
      nomeVendedor:   true,
    },
    orderBy: { nomeFantasia: 'asc' },
    take: Number(limite),
  });
}

async function buscarPorId(id) {
  return prisma.fornecedor.findUnique({
    where: { id },
    include: {
      materiais: {
        where: { ativo: true },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
            },
          },
        },
      },
    },
  });
}

async function listarPorMaterial(materialId) {
  return prisma.fornecedor.findMany({
    where: {
      ativo: true,
      materiais: { some: { materialId, ativo: true } },
    },
    include: {
      materiais: {
        where: { materialId, ativo: true },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

async function criar(data) {
  const { nomeFantasia, tipoFornecedor, telefone, cnpj, razaoSocial, nomeVendedor, imagemUrl } = data;
  if (!nomeFantasia?.trim()) throw { status: 400, message: 'nomeFantasia é obrigatório' };

  // Nome fantasia não pode se repetir entre fornecedores ativos.
  // Comparação normalizada (maiúsculas, sem acento) para pegar também
  // "Visual Premium" vs "VISUAL PREMIUM" vs "Visual  Prêmium".
  const nomeFantasiaNorm = _normalizarTextoComparacao(nomeFantasia);
  const ativos = await prisma.fornecedor.findMany({
    where: { ativo: true },
    select: { id: true, nomeFantasia: true },
  });
  const donoDoNome = ativos.find((f) => _normalizarTextoComparacao(f.nomeFantasia) === nomeFantasiaNorm) || null;
  if (donoDoNome) {
    throw {
      status: 409,
      message: `Já existe um fornecedor cadastrado com este nome fantasia (${donoDoNome.nomeFantasia}).`,
    };
  }

  const cnpjNormalizado = cnpj?.replace(/\D/g, '') || null;

  const dadosFornecedor = {
    nomeFantasia: nomeFantasia.trim(),
    tipoFornecedor: tipoFornecedor?.trim() ?? null,
    telefone: normalizarTelefone(telefone),
    cnpj: cnpjNormalizado,
    razaoSocial: razaoSocial?.trim() ?? null,
    nomeVendedor: nomeVendedor?.trim() ?? null,
    imagemUrl: imagemUrl?.trim() || null,
  };

  // cnpj é @unique no schema. Se já existir um fornecedor (mesmo que
  // inativo, ou seja, excluído via soft delete) com esse CNPJ, o
  // prisma.fornecedor.create() falha com "Unique constraint failed"
  // em vez de dar uma mensagem legível. Trata isso explicitamente:
  // - se o fornecedor existente estiver inativo, reativa e atualiza
  //   os dados (recupera o cadastro em vez de travar);
  // - se estiver ativo, retorna um erro claro para o usuário.
  if (cnpjNormalizado) {
    const existente = await prisma.fornecedor.findUnique({
      where: { cnpj: cnpjNormalizado },
    });

    if (existente) {
      if (existente.ativo) {
        throw {
          status: 409,
          message: `Já existe um fornecedor ativo cadastrado com este CNPJ (${existente.nomeFantasia}).`,
        };
      }
      return prisma.fornecedor.update({
        where: { id: existente.id },
        data: { ...dadosFornecedor, ativo: true },
      });
    }
  }

  return prisma.fornecedor.create({ data: dadosFornecedor });
}

async function atualizar(id, data) {
  data = data || {};

  const atual = await prisma.fornecedor.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Fornecedor não encontrado' };

  const updateData = {};
  if (data.nomeFantasia !== undefined) {
    updateData.nomeFantasia = data.nomeFantasia.trim();

    // Mesma checagem de nome duplicado do criar(), mas ignorando o
    // próprio registro que está sendo editado.
    const nomeFantasiaNorm = _normalizarTextoComparacao(updateData.nomeFantasia);
    const ativos = await prisma.fornecedor.findMany({
      where: { ativo: true, id: { not: id } },
      select: { id: true, nomeFantasia: true },
    });
    const donoDoNome = ativos.find((f) => _normalizarTextoComparacao(f.nomeFantasia) === nomeFantasiaNorm) || null;
    if (donoDoNome) {
      throw {
        status: 409,
        message: `Já existe outro fornecedor cadastrado com este nome fantasia (${donoDoNome.nomeFantasia}).`,
      };
    }
  }
  if (data.tipoFornecedor!== undefined) updateData.tipoFornecedor= data.tipoFornecedor?.trim() ?? null;
  if (data.telefone      !== undefined) updateData.telefone      = normalizarTelefone(data.telefone);
  if (data.cnpj          !== undefined) updateData.cnpj          = data.cnpj?.replace(/\D/g, '') || null;
  if (data.razaoSocial   !== undefined) updateData.razaoSocial   = data.razaoSocial?.trim() ?? null;
  if (data.nomeVendedor  !== undefined) updateData.nomeVendedor  = data.nomeVendedor?.trim() ?? null;
  if (data.imagemUrl     !== undefined) updateData.imagemUrl     = data.imagemUrl?.trim() || null;

  // Mesmo cuidado do criar(): cnpj é @unique, então trocar para um CNPJ
  // já usado por outro fornecedor (ativo ou inativo) quebraria o update
  // com um erro pouco legível. Valida antes e dá uma mensagem clara.
  if (updateData.cnpj) {
    const donoDoCnpj = await prisma.fornecedor.findUnique({
      where: { cnpj: updateData.cnpj },
    });
    if (donoDoCnpj && donoDoCnpj.id !== id) {
      throw {
        status: 409,
        message: `Já existe outro fornecedor cadastrado com este CNPJ (${donoDoCnpj.nomeFantasia}).`,
      };
    }
  }

  return prisma.fornecedor.update({ where: { id }, data: updateData });
}

async function remover(id) {
  const atual = await prisma.fornecedor.findUnique({ where: { id } });
  if (!atual) throw { status: 404, message: 'Fornecedor não encontrado' };

  return prisma.$transaction([
    prisma.fornecedorMaterial.updateMany({
      where: { fornecedorId: id },
      data: { ativo: false },
    }),
    prisma.orcamentoItem.updateMany({
      where: {
        fornecedorId: id,
        orcamento: {
          status: { in: ['ABERTO', 'AGUARDANDO_APROVACAO'] },
        },
      },
      data: { fornecedorId: null, selecionado: false },
    }),
    prisma.fornecedor.update({
      where: { id },
      data: { ativo: false },
    }),
  ]);
}

function _normalizarPrecoDecimal(valor) {
  if (valor == null || valor === '') return null;
  const str = String(valor).trim();
  const num = Number(str);
  if (isNaN(num)) return null;
  return parseFloat(num.toFixed(6)).toString();
}

async function vincularMaterial(fornecedorId, materialId, preco, precoMetroQuadrado, precoUnidadeMedida) {
  const precoVal   = _normalizarPrecoDecimal(preco);
  const precoM2Val = _normalizarPrecoDecimal(precoMetroQuadrado);
  const precoUnidadeMedidaVal = _normalizarPrecoDecimal(precoUnidadeMedida);

  return prisma.fornecedorMaterial.upsert({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    create: {
      fornecedorId,
      materialId,
      preco: precoVal,
      precoMetroQuadrado: precoM2Val,
      precoUnidadeMedida: precoUnidadeMedidaVal,
      ativo: true,
    },
    update: {
      preco: precoVal,
      precoMetroQuadrado: precoM2Val,
      precoUnidadeMedida: precoUnidadeMedidaVal,
      ativo: true,
    },
  });
}

async function desvincularMaterial(fornecedorId, materialId) {
  return prisma.fornecedorMaterial.update({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    data: { ativo: false },
  });
}

async function atualizarPrecoVinculo(fornecedorId, materialId, data) {
  const updateData = { ...data };
  if (updateData.preco !== undefined) updateData.preco = _normalizarPrecoDecimal(updateData.preco);
  if (updateData.precoMetroQuadrado !== undefined) updateData.precoMetroQuadrado = _normalizarPrecoDecimal(updateData.precoMetroQuadrado);
  if (updateData.precoUnidadeMedida !== undefined) updateData.precoUnidadeMedida = _normalizarPrecoDecimal(updateData.precoUnidadeMedida);

  return prisma.fornecedorMaterial.update({
    where: { fornecedorId_materialId: { fornecedorId, materialId } },
    data: updateData,
  });
}

async function listarTipos() {
  const linhas = await prisma.fornecedor.findMany({
    where: { ativo: true, tipoFornecedor: { not: null } },
    select: { tipoFornecedor: true },
    distinct: ['tipoFornecedor'],
    orderBy: { tipoFornecedor: 'asc' },
  });
  return linhas
    .map((l) => l.tipoFornecedor)
    .filter(Boolean)
    .sort();
}

module.exports = {
  listar,
  listarPaginado,
  listarTipos,
  buscarParaVinculo,
  buscarPorId,
  listarPorMaterial,
  criar,
  atualizar,
  remover,
  vincularMaterial,
  desvincularMaterial,
  atualizarPrecoVinculo,
  verificarSemelhantes,
};