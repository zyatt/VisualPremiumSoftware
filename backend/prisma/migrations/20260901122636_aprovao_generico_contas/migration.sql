-- CreateEnum
CREATE TYPE "StatusContaPagar" AS ENUM ('PENDENTE', 'PAGO', 'VENCIDO', 'CANCELADO');

-- CreateEnum
CREATE TYPE "OrigemNotaFiscal" AS ENUM ('XML_MANUAL', 'CERTIFICADO_A1');

-- DropIndex
DROP INDEX "orcamento_itens_orcamentoId_materialId_fornecedorId_key";

-- AlterTable
ALTER TABLE "materiais" ADD COLUMN     "aguardandoAprovacao" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "aprovadoEm" TIMESTAMP(3),
ADD COLUMN     "aprovadoPorId" INTEGER,
ADD COLUMN     "aprovadoPorNome" TEXT,
ADD COLUMN     "criadoPorId" INTEGER,
ADD COLUMN     "criadoPorNome" TEXT,
ADD COLUMN     "descricao" TEXT,
ADD COLUMN     "ehGenerico" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "materialGenericoId" INTEGER;

-- AlterTable
ALTER TABLE "orcamento_itens" ADD COLUMN     "descricaoConfirmada" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "empresas" (
    "id" SERIAL NOT NULL,
    "nome" TEXT NOT NULL,
    "cnpj" TEXT NOT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "empresas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "certificados_digitais" (
    "id" SERIAL NOT NULL,
    "empresaId" INTEGER NOT NULL,
    "arquivoNome" TEXT NOT NULL,
    "arquivoPath" TEXT NOT NULL,
    "senhaCriptografada" TEXT NOT NULL,
    "validade" TIMESTAMP(3),
    "ativo" BOOLEAN NOT NULL DEFAULT false,
    "ultimaConsultaEm" TIMESTAMP(3),
    "ultimoErro" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "certificados_digitais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notas_fiscais" (
    "id" SERIAL NOT NULL,
    "empresaId" INTEGER,
    "chaveAcesso" TEXT NOT NULL,
    "numero" TEXT,
    "serie" TEXT,
    "dataEmissao" TIMESTAMP(3),
    "valorTotal" DECIMAL(15,2),
    "emitenteCnpj" TEXT,
    "emitenteNome" TEXT,
    "destinatarioCnpj" TEXT,
    "destinatarioNome" TEXT,
    "xmlOriginal" TEXT,
    "origem" "OrigemNotaFiscal" NOT NULL DEFAULT 'XML_MANUAL',
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "notas_fiscais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "contas_pagar" (
    "id" SERIAL NOT NULL,
    "empresaId" INTEGER,
    "notaFiscalId" INTEGER,
    "descricao" TEXT NOT NULL,
    "numeroDocumento" TEXT,
    "emitenteNome" TEXT,
    "emitenteCnpj" TEXT,
    "valor" DECIMAL(15,2) NOT NULL,
    "dataEmissao" TIMESTAMP(3),
    "dataVencimento" TIMESTAMP(3) NOT NULL,
    "dataPagamento" TIMESTAMP(3),
    "status" "StatusContaPagar" NOT NULL DEFAULT 'PENDENTE',
    "formaPagamento" TEXT,
    "categoria" TEXT,
    "observacao" TEXT,
    "anexoUrl" TEXT,
    "criadoPorId" INTEGER,
    "criadoPorNome" TEXT,
    "pagoPorId" INTEGER,
    "pagoPorNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "contas_pagar_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "empresas_cnpj_key" ON "empresas"("cnpj");

-- CreateIndex
CREATE UNIQUE INDEX "certificados_digitais_empresaId_key" ON "certificados_digitais"("empresaId");

-- CreateIndex
CREATE UNIQUE INDEX "notas_fiscais_chaveAcesso_key" ON "notas_fiscais"("chaveAcesso");

-- CreateIndex
CREATE INDEX "notas_fiscais_empresaId_idx" ON "notas_fiscais"("empresaId");

-- CreateIndex
CREATE UNIQUE INDEX "contas_pagar_notaFiscalId_key" ON "contas_pagar"("notaFiscalId");

-- CreateIndex
CREATE INDEX "contas_pagar_empresaId_idx" ON "contas_pagar"("empresaId");

-- CreateIndex
CREATE INDEX "contas_pagar_status_idx" ON "contas_pagar"("status");

-- CreateIndex
CREATE INDEX "contas_pagar_dataVencimento_idx" ON "contas_pagar"("dataVencimento");

-- CreateIndex
CREATE INDEX "materiais_aguardandoAprovacao_idx" ON "materiais"("aguardandoAprovacao");

-- CreateIndex
CREATE INDEX "materiais_ehGenerico_idx" ON "materiais"("ehGenerico");

-- CreateIndex
CREATE INDEX "materiais_materialGenericoId_idx" ON "materiais"("materialGenericoId");

-- AddForeignKey
ALTER TABLE "materiais" ADD CONSTRAINT "materiais_materialGenericoId_fkey" FOREIGN KEY ("materialGenericoId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "certificados_digitais" ADD CONSTRAINT "certificados_digitais_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "empresas"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notas_fiscais" ADD CONSTRAINT "notas_fiscais_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "empresas"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contas_pagar" ADD CONSTRAINT "contas_pagar_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "empresas"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contas_pagar" ADD CONSTRAINT "contas_pagar_notaFiscalId_fkey" FOREIGN KEY ("notaFiscalId") REFERENCES "notas_fiscais"("id") ON DELETE SET NULL ON UPDATE CASCADE;
