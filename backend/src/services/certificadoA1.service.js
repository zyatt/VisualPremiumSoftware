// services/certificadoA1.service.js
//
// Encapsula tudo relacionado ao certificado digital A1 de cada empresa.
// HOJE: só cadastro/armazenamento seguro do certificado (upload do .pfx/.p12
// + senha). A busca automática de NF-e na SEFAZ (DistDFe / NFeDistribuicaoDFe)
// fica com o "encaixe" pronto em `buscarNotasNaSefaz`, mas desligada até
// existir certificado ativo — quando você subir os certificados reais, é só
// implementar a chamada ao webservice ali dentro (bibliotecas comuns pra
// isso em Node: `node-forge` para ler o .pfx, e uma lib de SOAP/mTLS para
// falar com a SEFAZ, ex: `soap` + `https.Agent({ pfx, passphrase })`).
//
// Dependências sugeridas quando for implementar de fato:
//   npm install node-forge
//
// SEGURANÇA: a senha do certificado NUNCA é salva em texto puro — usamos
// criptografia simétrica (AES-256-GCM) com uma chave de ambiente
// (CERT_ENCRYPTION_KEY, 32 bytes). O arquivo .pfx fica fora da pasta
// pública /uploads.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ALGORITMO = 'aes-256-gcm';
const PASTA_CERTIFICADOS = path.join(__dirname, '..', 'storage', 'certificados');

function getChaveEnv() {
  const chave = process.env.CERT_ENCRYPTION_KEY;
  if (!chave || chave.length < 32) {
    throw new Error(
      'CERT_ENCRYPTION_KEY não configurada (ou menor que 32 caracteres) nas variáveis de ambiente. ' +
      'Defina uma chave forte antes de cadastrar certificados A1.'
    );
  }
  return Buffer.from(chave.slice(0, 32));
}

function criptografarSenha(senhaPlana) {
  const chave = getChaveEnv();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGORITMO, chave, iv);
  const encrypted = Buffer.concat([cipher.update(senhaPlana, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString('base64');
}

function descriptografarSenha(senhaCriptografada) {
  const chave = getChaveEnv();
  const bruto = Buffer.from(senhaCriptografada, 'base64');
  const iv = bruto.subarray(0, 12);
  const tag = bruto.subarray(12, 28);
  const encrypted = bruto.subarray(28);
  const decipher = crypto.createDecipheriv(ALGORITMO, chave, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
}

function garantirPastaCertificados() {
  fs.mkdirSync(PASTA_CERTIFICADOS, { recursive: true });
}

/**
 * Salva o arquivo do certificado (.pfx/.p12) em disco, fora da pasta pública,
 * e retorna o caminho salvo.
 */
function salvarArquivoCertificado(empresaId, bufferArquivo, nomeOriginal) {
  garantirPastaCertificados();
  const extensao = path.extname(nomeOriginal) || '.pfx';
  const nomeArquivo = `empresa_${empresaId}_${Date.now()}${extensao}`;
  const destino = path.join(PASTA_CERTIFICADOS, nomeArquivo);
  fs.writeFileSync(destino, bufferArquivo);
  return destino;
}

/**
 * PLACEHOLDER — implementar quando os certificados reais estiverem
 * cadastrados. Deve:
 *   1. Ler o .pfx com node-forge usando a senha descriptografada.
 *   2. Montar o envelope SOAP para o serviço NFeDistribuicaoDFe da SEFAZ,
 *      usando mTLS com o certificado.
 *   3. Paginar via NSU até não haver mais documentos novos.
 *   4. Para cada docZip retornado, decodificar (base64 + gzip) o XML e
 *      chamar `extrairDadosNFe` (notaFiscalXml.service.js) + persistir
 *      como NotaFiscal (origem: CERTIFICADO_A1) e gerar a ContaPagar.
 */
async function buscarNotasNaSefaz(certificadoDigital) {
  throw new Error(
    'Busca automática de NF-e via certificado A1 ainda não implementada. ' +
    'Cadastre o certificado normalmente — a busca automática será ligada ' +
    'quando o certificado de produção estiver disponível.'
  );
}

module.exports = {
  criptografarSenha,
  descriptografarSenha,
  salvarArquivoCertificado,
  buscarNotasNaSefaz,
};