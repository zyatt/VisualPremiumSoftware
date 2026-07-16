-- DropForeignKey
ALTER TABLE "audit_log_materiais" DROP CONSTRAINT "audit_log_materiais_materialId_fkey";

-- DropForeignKey
ALTER TABLE "manutencoes_veiculo" DROP CONSTRAINT "manutencoes_veiculo_veiculoId_fkey";

-- DropForeignKey
ALTER TABLE "mensagens_chat" DROP CONSTRAINT "mensagens_chat_destinatarioId_fkey";

-- DropForeignKey
ALTER TABLE "mensagens_chat" DROP CONSTRAINT "mensagens_chat_remetenteId_fkey";

-- AlterTable
ALTER TABLE "adicionais_solicitacao_material" ADD COLUMN     "estoque" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "estoqueEm" TIMESTAMP(3),
ADD COLUMN     "estoquePorId" INTEGER,
ADD COLUMN     "estoquePorNome" TEXT;

-- AlterTable
ALTER TABLE "audit_log_materiais" ADD COLUMN     "materialCategoriaSnap" TEXT,
ADD COLUMN     "materialComprimentoSnap" TEXT,
ADD COLUMN     "materialEspessuraSnap" TEXT,
ADD COLUMN     "materialIdentificadorSnap" TEXT,
ADD COLUMN     "materialLarguraSnap" TEXT,
ADD COLUMN     "materialMedidaSnap" TEXT,
ADD COLUMN     "materialNomeSnap" TEXT,
ADD COLUMN     "materialUnidadeSnap" TEXT,
ALTER COLUMN "materialId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "fornecedores" ADD COLUMN     "imagemUrl" TEXT;

-- AlterTable
ALTER TABLE "itens_solicitacao_material" ADD COLUMN     "estoque" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "estoqueEm" TIMESTAMP(3),
ADD COLUMN     "estoquePorId" INTEGER,
ADD COLUMN     "estoquePorNome" TEXT;

-- CreateTable
CREATE TABLE "estoque_producao" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL DEFAULT 0,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "estoque_producao_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "movimentacoes_producao" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "tipo" TEXT NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "numeroOS" TEXT,
    "observacao" TEXT,
    "usuarioNome" TEXT,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "movimentacoes_producao_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "estoque_producao_materialId_key" ON "estoque_producao"("materialId");

-- CreateIndex
CREATE INDEX "movimentacoes_producao_materialId_idx" ON "movimentacoes_producao"("materialId");

-- CreateIndex
CREATE INDEX "movimentacoes_producao_numeroOS_idx" ON "movimentacoes_producao"("numeroOS");

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_remetenteId_fkey" FOREIGN KEY ("remetenteId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_destinatarioId_fkey" FOREIGN KEY ("destinatarioId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "estoque_producao" ADD CONSTRAINT "estoque_producao_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_producao" ADD CONSTRAINT "movimentacoes_producao_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_log_materiais" ADD CONSTRAINT "audit_log_materiais_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "manutencoes_veiculo" ADD CONSTRAINT "manutencoes_veiculo_veiculoId_fkey" FOREIGN KEY ("veiculoId") REFERENCES "veiculos"("id") ON DELETE CASCADE ON UPDATE CASCADE;
