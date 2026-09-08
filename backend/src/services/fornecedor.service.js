const prisma = require('../utils/prisma');
const materialSvc = require('./material.service');

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
        // `ativo: true` filtra pelo vínculo (FornecedorMaterial) e
        // `material: { ativo: true }` filtra pelo Material relacionado —
        // Prisma permite condicionar a listagem do lado "muitos" (materiais)
        // por um campo da relação para-um (material) dentro do mesmo where,
        // mas NÃO aceita um `where` dentro de um include de relação
        // para-um isolado (por isso o filtro fica aqui, não em `material`).
        where: { ativo: true, material: { ativo: true } },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              descricao: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
              ativo: true,
              ehGenerico: true,
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
        // `ativo: true` filtra pelo vínculo (FornecedorMaterial) e
        // `material: { ativo: true }` filtra pelo Material relacionado —
        // Prisma permite condicionar a listagem do lado "muitos" (materiais)
        // por um campo da relação para-um (material) dentro do mesmo where,
        // mas NÃO aceita um `where` dentro de um include de relação
        // para-um isolado (por isso o filtro fica aqui, não em `material`).
        where: { ativo: true, material: { ativo: true } },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              descricao: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
              ativo: true,
              ehGenerico: true,
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
        // `ativo: true` filtra pelo vínculo (FornecedorMaterial) e
        // `material: { ativo: true }` filtra pelo Material relacionado —
        // Prisma permite condicionar a listagem do lado "muitos" (materiais)
        // por um campo da relação para-um (material) dentro do mesmo where,
        // mas NÃO aceita um `where` dentro de um include de relação
        // para-um isolado (por isso o filtro fica aqui, não em `material`).
        where: { ativo: true, material: { ativo: true } },
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              descricao: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
              ativo: true,
              ehGenerico: true,
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
        // Sem este `include.material`, o vínculo volta sem os dados do
        // Material relacionado (nome, descricao, etc.) — o front usa
        // `materialDescricao` para mostrar a descrição da variante
        // (ex.: "ABC" de "TINTA · ABC") ao lado do fornecedor na tela
        // "Vincular por Material", e sem isso o campo chega sempre null.
        include: {
          material: {
            select: {
              id: true,
              nome: true,
              descricao: true,
              identificador: true,
              medida: true,
              espessura: true,
              unidade: true,
              largura: true,
              comprimento: true,
              ativo: true,
              ehGenerico: true,
            },
          },
        },
      },
    },
    orderBy: { nomeFantasia: 'asc' },
  });
}

/**
 * Resolve o id do Material filho (variante) de um genérico a partir da
 * descrição digitada, SEM criar nada — usado pela tela de "Vincular por
 * Material" para saber quais fornecedores já têm aquela variante
 * vinculada enquanto o usuário ainda está digitando a descrição. Criar o
 * filho aqui geraria variantes "fantasma" toda vez que alguém apenas
 * pesquisasse, então essa função só enxerga o que já existe.
 *
 * A comparação precisa casar exatamente com a usada em
 * material.service.js::resolverOuCriarFilho — `equals` case-insensitive
 * após trim(), SEM remover acentos — senão esta função e aquela podiam
 * discordar sobre o que conta como "a mesma variante" (ex.: uma achando
 * a variante existente e a outra criando um filho novo para o mesmo
 * texto).
 *
 * @returns {Promise<number|null>} id do Material filho, ou null se a
 *   variante ainda não existe.
 */
async function resolverFilhoPorDescricao(materialGenericoId, descricao) {
  const descTrimmed = descricao?.trim();
  if (!descTrimmed) return null;

  const filho = await prisma.material.findFirst({
    where: {
      materialGenericoId,
      descricao: { equals: descTrimmed, mode: 'insensitive' },
    },
    select: { id: true },
  });
  return filho ? filho.id : null;
}

/**
 * Lista os fornecedores que já têm vinculada a variante (filho) de um
 * material genérico correspondente à descrição informada. Se a variante
 * ainda não existir, retorna lista vazia (ninguém pode estar vinculado a
 * algo que não existe) em vez de erro — a UI trata isso como "nenhum
 * fornecedor vinculado ainda".
 */
async function listarPorMaterialGenericoEDescricao(materialGenericoId, descricao) {
  const materialIdReal = await resolverFilhoPorDescricao(materialGenericoId, descricao);
  if (!materialIdReal) return [];
  return listarPorMaterial(materialIdReal);
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

async function _garantirVinculoGenerico(fornecedorId, materialGenericoId) {
  // Vínculo "de presença" do material genérico com o fornecedor, sem
  // preço (o genérico nunca tem preço próprio, só suas variantes).
  // Ver comentário em vincularMaterial() para o motivo.
  await prisma.fornecedorMaterial.upsert({
    where: { fornecedorId_materialId: { fornecedorId, materialId: materialGenericoId } },
    create: {
      fornecedorId,
      materialId: materialGenericoId,
      preco: 0,
      precoMetroQuadrado: 0,
      precoUnidadeMedida: 0,
      ativo: true,
    },
    update: {
      ativo: true,
    },
  });
}

async function vincularMaterial(fornecedorId, materialId, preco, precoMetroQuadrado, precoUnidadeMedida, descricao) {
  const precoVal   = _normalizarPrecoDecimal(preco);
  const precoM2Val = _normalizarPrecoDecimal(precoMetroQuadrado);
  const precoUnidadeMedidaVal = _normalizarPrecoDecimal(precoUnidadeMedida);

  // Material genérico não pode receber vínculo/preço diretamente — o
  // vínculo tem que ser sempre com a variante concreta (o Material
  // filho, que carrega a descrição). Antes, a busca de materiais usada
  // na tela de Fornecedores (GET /materiais) nem mostra os filhos por
  // padrão, então a UI só oferecia o genérico para escolher — e o
  // vínculo acabava ficando preso a ele, "sumindo" a descrição.
  // Agora: se vier uma "descricao" junto, resolve (ou cria) o filho e
  // vincula nele, do mesmo jeito que o orçamento já faz.
  const material = await prisma.material.findUnique({
    where: { id: materialId },
    select: { id: true, ehGenerico: true, nome: true },
  });
  if (!material) throw { status: 404, message: 'Material não encontrado.' };

  let materialIdReal = materialId;
  if (material.ehGenerico) {
    const desc = descricao != null && String(descricao).trim() ? String(descricao).trim() : null;
    if (!desc) {
      throw {
        status: 400,
        message: `"${material.nome}" é um material genérico: informe a descrição da variante (ex.: a cor) para vincular o preço do fornecedor.`,
      };
    }
    materialIdReal = (await materialSvc.resolverOuCriarFilho(materialId, desc)).id;

    // Além de vincular a variante concreta (acima), garante que o
    // material genérico "pai" também fique marcado como vinculado a
    // este fornecedor. Sem isso, o pai nunca aparece na lista de "já
    // vinculados" na tela de Fornecedores/Ordem de Compra, mesmo
    // depois de o usuário vincular várias variantes dele: ele some
    // do array `fornecedor.materiais` e a UI mostra "Novo vínculo"
    // pra ele pra sempre, obrigando o usuário a sempre expandir e
    // escolher a variante certa mesmo pra adicionar outra variante
    // nova depois.
    await _garantirVinculoGenerico(fornecedorId, materialId);
  }

  return prisma.fornecedorMaterial.upsert({
    where: { fornecedorId_materialId: { fornecedorId, materialId: materialIdReal } },
    create: {
      fornecedorId,
      materialId: materialIdReal,
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
  listarPorMaterialGenericoEDescricao,
  criar,
  atualizar,
  remover,
  vincularMaterial,
  desvincularMaterial,
  atualizarPrecoVinculo,
  verificarSemelhantes,
  // Exportado para o ordemCompra.service.js reaproveitar ao sincronizar
  // vínculos fornecedor↔material a partir dos itens de uma OC (o mesmo
  // "vínculo de presença" do genérico precisa acontecer nos dois fluxos:
  // vincular manualmente na tela de Fornecedores, e vincular
  // implicitamente ao salvar/atualizar uma Ordem de Compra).
  _garantirVinculoGenerico,
};