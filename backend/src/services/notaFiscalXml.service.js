// services/notaFiscalXml.service.js
//
// Extrai os dados relevantes de um documento fiscal eletrônico para
// preencher automaticamente uma Conta a Pagar. Suporta dois formatos:
//
//   1) NF-e (modelo 55, padrão nacional SEFAZ) — mercadoria/produto.
//      Aceita tanto o XML "puro" (<nfeProc>/<NFe>) quanto envelopes de
//      distribuição — cobre a maioria dos casos reais de nota baixada
//      do fornecedor.
//
//   2) NFS-e (nota de serviço) — o layout varia por prefeitura/software
//      municipal (ABRASF, Elotech, Ginfes, etc.), então o parser aqui é
//      tolerante: procura os campos comuns (Numero, ValorServicos,
//      Prestador/Tomador, DataEmissao...) em vários caminhos possíveis
//      dentro do XML, ao invés de exigir uma estrutura fixa. Cobre o
//      caso de vir dentro de um envelope SOAP (<Envelope>/<Body>/...)
//      ou como XML solto (<CompNfse>/<Nfse>/<InfNfse>).
//
// Dependência: npm install fast-xml-parser
//
// O tipo do documento é detectado automaticamente a partir do próprio
// XML — o chamador (controller) não precisa saber de antemão qual é.

const { XMLParser } = require('fast-xml-parser');

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  removeNSPrefix: true, // remove prefixos de namespace (ex: "nfe:infNFe" -> "infNFe", "ns2:Numero" -> "Numero")
  parseTagValue: false,
  trimValues: true,
});

class NotaFiscalXmlError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotaFiscalXmlError';
    this.status = 400;
  }
}

function primeiro(valor) {
  return Array.isArray(valor) ? valor[0] : valor;
}

function paraNumero(valor) {
  if (valor === undefined || valor === null || valor === '') return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}

function paraData(valor) {
  if (!valor) return null;
  const d = new Date(valor);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Busca em profundidade (BFS) pela primeira ocorrência de uma tag com
 * qualquer um dos nomes informados, em qualquer nível do objeto. Usado
 * pelo parser de NFS-e para tolerar variação de estrutura entre
 * diferentes softwares municipais (com/sem envelope SOAP, profundidade
 * variável, etc.) sem precisar de um caminho fixo tipo `a.b.c.d`.
 */
function buscarProfundo(obj, nomes) {
  if (obj === null || typeof obj !== 'object') return undefined;
  const fila = [obj];
  while (fila.length) {
    const atual = fila.shift();
    if (atual === null || typeof atual !== 'object') continue;
    for (const chave of Object.keys(atual)) {
      if (nomes.includes(chave)) {
        const valor = primeiro(atual[chave]);
        if (valor !== undefined && valor !== null && valor !== '') return valor;
      }
    }
    for (const chave of Object.keys(atual)) {
      const valor = atual[chave];
      if (Array.isArray(valor)) {
        for (const item of valor) fila.push(item);
      } else if (typeof valor === 'object' && valor !== null) {
        fila.push(valor);
      }
    }
  }
  return undefined;
}

// ---------------------------------------------------------------------
// NF-e (modelo 55) — produto/mercadoria
// ---------------------------------------------------------------------

function extrairNFe(doc) {
  // Pode vir como nfeProc.NFe.infNFe ou direto NFe.infNFe
  const nfe = doc?.nfeProc?.NFe ?? doc?.NFe;
  if (!nfe) {
    throw new NotaFiscalXmlError('O XML enviado não parece ser uma Nota Fiscal Eletrônica (NF-e) válida.');
  }

  const infNFe = primeiro(nfe.infNFe);
  if (!infNFe) {
    throw new NotaFiscalXmlError('Estrutura da NF-e não encontrada no XML (tag infNFe ausente).');
  }

  // Chave de acesso: normalmente no atributo Id="NFe<44 dígitos>" de infNFe,
  // ou no protNFe (nfeProc.protNFe.infProt.chNFe)
  let chaveAcesso =
    doc?.nfeProc?.protNFe?.infProt?.chNFe ??
    (infNFe['@_Id'] || '').replace(/^NFe/i, '');

  chaveAcesso = (chaveAcesso || '').trim();
  if (!/^\d{44}$/.test(chaveAcesso)) {
    throw new NotaFiscalXmlError('Não foi possível identificar a chave de acesso (44 dígitos) desta NF-e.');
  }

  const ide = infNFe.ide ?? {};
  const emit = infNFe.emit ?? {};
  const dest = infNFe.dest ?? {};
  const total = infNFe.total?.ICMSTot ?? {};

  const emitEndereco = emit.enderEmit ?? {};
  const destEndereco = dest.enderDest ?? {};

  return {
    tipo: 'NFE',
    chaveAcesso,
    numero: ide.nNF !== undefined ? String(ide.nNF) : null,
    serie: ide.serie !== undefined ? String(ide.serie) : null,
    dataEmissao: paraData(ide.dhEmi ?? ide.dEmi ?? null),
    valorTotal: paraNumero(total.vNF),
    emitenteCnpj: emit.CNPJ ? String(emit.CNPJ) : null,
    emitenteNome: emit.xNome ? String(emit.xNome) : null,
    emitenteMunicipio: emitEndereco.xMun ? String(emitEndereco.xMun) : null,
    destinatarioCnpj: dest.CNPJ ? String(dest.CNPJ) : (dest.CPF ? String(dest.CPF) : null),
    destinatarioNome: dest.xNome ? String(dest.xNome) : null,
    destinatarioMunicipio: destEndereco.xMun ? String(destEndereco.xMun) : null,
  };
}

// ---------------------------------------------------------------------
// NFS-e (nota de serviço) — layout varia por prefeitura/software
// municipal (ABRASF, Elotech, Ginfes, DSF, ISSNet...). Em vez de exigir
// um caminho fixo, busca os campos em profundidade dentro do XML.
// ---------------------------------------------------------------------

function extrairNFSe(doc) {
  // Chave/identificador único da nota. Prioridade:
  //   1) ChaveAcessoNacional (padrão novo, 50 dígitos, quando existe)
  //   2) CodigoVerificacao + Numero (praticamente todo layout tem algo assim)
  //   3) IdDps (identificador da Declaração de Prestação de Serviço, padrão novo)
  const chaveNacional = buscarProfundo(doc, ['ChaveAcessoNacional']);
  const codigoVerificacao = buscarProfundo(doc, ['CodigoVerificacao']);
  const numero = buscarProfundo(doc, ['Numero', 'numeroNfse', 'NumeroNfse']);
  const idDps = buscarProfundo(doc, ['IdDps']);

  let chaveAcesso = null;
  if (chaveNacional) {
    chaveAcesso = `NFSE-${String(chaveNacional).trim()}`;
  } else if (numero && codigoVerificacao) {
    chaveAcesso = `NFSE-${String(numero).trim()}-${String(codigoVerificacao).trim()}`;
  } else if (idDps) {
    chaveAcesso = `NFSE-${String(idDps).trim()}`;
  }

  if (!chaveAcesso) {
    throw new NotaFiscalXmlError(
      'Não foi possível identificar um número/código de verificação nesta NFS-e.'
    );
  }

  const dataEmissao = buscarProfundo(doc, ['DataEmissao', 'dataEmissao']);
  const valorServicos = buscarProfundo(doc, ['ValorServicos', 'ValorLiquidoNfse', 'valorLiquido']);

  // Prestador = quem emitiu/prestou o serviço (equivalente ao "emit" da NF-e)
  const prestador = buscarProfundo(doc, ['PrestadorServico', 'Prestador', 'prest']);
  const prestadorCnpj = prestador ? buscarProfundo(prestador, ['Cnpj', 'CNPJ']) : buscarProfundo(doc, ['Cnpj', 'CNPJ']);
  const prestadorNome = prestador ? buscarProfundo(prestador, ['RazaoSocial', 'xNome', 'NomeFantasia']) : null;

  // Tomador = quem contratou/recebeu o serviço (equivalente ao "dest" da NF-e)
  const tomador = buscarProfundo(doc, ['Tomador', 'tomador']);
  const tomadorCnpj = tomador ? buscarProfundo(tomador, ['Cnpj', 'CNPJ']) : null;
  const tomadorCpf = tomador ? buscarProfundo(tomador, ['Cpf', 'CPF']) : null;
  const tomadorNome = tomador ? buscarProfundo(tomador, ['RazaoSocial', 'xNome']) : null;

  const municipio = buscarProfundo(doc, ['CodigoMunicipio']);

  return {
    tipo: 'NFSE',
    chaveAcesso,
    numero: numero !== undefined && numero !== null ? String(numero) : null,
    serie: null, // NFS-e não tem série no sentido da NF-e
    dataEmissao: paraData(dataEmissao),
    valorTotal: paraNumero(valorServicos),
    emitenteCnpj: prestadorCnpj ? String(prestadorCnpj) : null,
    emitenteNome: prestadorNome ? String(prestadorNome) : null,
    emitenteMunicipio: municipio ? String(municipio) : null,
    destinatarioCnpj: tomadorCnpj ? String(tomadorCnpj) : (tomadorCpf ? String(tomadorCpf) : null),
    destinatarioNome: tomadorNome ? String(tomadorNome) : null,
    destinatarioMunicipio: null,
  };
}

/**
 * Detecta se o documento parseado é uma NF-e ou uma NFS-e, olhando quais
 * tags estão presentes — sem depender de um caminho fixo, já que ambos
 * podem vir dentro de envelopes diferentes.
 */
function detectarTipo(doc) {
  if (doc?.nfeProc || doc?.NFe) return 'NFE';

  const marcaNfse = buscarProfundo(doc, [
    'InfNfse', 'Nfse', 'CompNfse', 'EnviarLoteRpsSincronoResposta',
    'ValoresNfse', 'DeclaracaoPrestacaoServico',
  ]);
  if (marcaNfse) return 'NFSE';

  return null;
}

/**
 * @param {string} xmlString conteúdo bruto do arquivo .xml
 * @returns {{
 *   tipo: 'NFE'|'NFSE',
 *   chaveAcesso: string,
 *   numero: string|null,
 *   serie: string|null,
 *   dataEmissao: Date|null,
 *   valorTotal: number|null,
 *   emitenteCnpj: string|null,
 *   emitenteNome: string|null,
 *   destinatarioCnpj: string|null,
 *   destinatarioNome: string|null,
 * }}
 */
function extrairDadosNFe(xmlString) {
  if (!xmlString || typeof xmlString !== 'string' || !xmlString.trim()) {
    throw new NotaFiscalXmlError('Arquivo XML vazio ou inválido.');
  }

  let doc;
  try {
    doc = parser.parse(xmlString);
  } catch (e) {
    throw new NotaFiscalXmlError('Não foi possível ler o XML enviado. Verifique se o arquivo não está corrompido.');
  }

  const tipo = detectarTipo(doc);

  if (tipo === 'NFE') return extrairNFe(doc);
  if (tipo === 'NFSE') return extrairNFSe(doc);

  throw new NotaFiscalXmlError(
    'O XML enviado não parece ser uma NF-e ou NFS-e reconhecida pelo sistema.'
  );
}

module.exports = { extrairDadosNFe, NotaFiscalXmlError };