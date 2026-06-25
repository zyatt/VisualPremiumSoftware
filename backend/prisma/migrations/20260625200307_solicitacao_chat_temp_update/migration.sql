-- DropForeignKey
ALTER TABLE "ordem_compra_itens" DROP CONSTRAINT "ordem_compra_itens_materialId_fkey";

-- AlterTable
ALTER TABLE "materiais" ADD COLUMN     "criadoPorNome" TEXT,
ADD COLUMN     "desativaEm" TIMESTAMP(3),
ADD COLUMN     "observacaoTemporario" TEXT,
ADD COLUMN     "temporario" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "movimentacoes_estoque" ADD COLUMN     "materialOrigemId" INTEGER;

-- AlterTable
ALTER TABLE "orcamento_itens" ADD COLUMN     "observacao" TEXT;

-- AlterTable
ALTER TABLE "ordem_compra_itens" ALTER COLUMN "materialId" DROP NOT NULL;

-- CreateTable
CREATE TABLE "mensagens_chat" (
    "id" SERIAL NOT NULL,
    "remetenteId" INTEGER NOT NULL,
    "destinatarioId" INTEGER NOT NULL,
    "conteudo" TEXT NOT NULL,
    "lida" BOOLEAN NOT NULL DEFAULT false,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "mensagens_chat_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "solicitacoes_material" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "quantidade" DECIMAL(10,3) NOT NULL,
    "numeroOS" TEXT NOT NULL,
    "nomeCliente" TEXT NOT NULL,
    "dataSolicitacao" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dataNecessidade" TIMESTAMP(3) NOT NULL,
    "andamento" TEXT NOT NULL DEFAULT 'EM_ANDAMENTO',
    "observacao" TEXT,
    "imagemUrl" TEXT,
    "usuarioId" INTEGER NOT NULL,
    "usuarioNome" TEXT NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "solicitacoes_material_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "visualizacoes_solicitacao" (
    "id" SERIAL NOT NULL,
    "usuarioId" INTEGER NOT NULL,
    "solicitacaoId" INTEGER NOT NULL,
    "visualizadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "visualizacoes_solicitacao_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "logs_edicao_solicitacao" (
    "id" SERIAL NOT NULL,
    "solicitacaoId" INTEGER NOT NULL,
    "editorId" INTEGER NOT NULL,
    "editorNome" TEXT NOT NULL,
    "antes" JSONB NOT NULL,
    "depois" JSONB NOT NULL,
    "editadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "logs_edicao_solicitacao_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "mensagens_chat_remetenteId_destinatarioId_idx" ON "mensagens_chat"("remetenteId", "destinatarioId");

-- CreateIndex
CREATE INDEX "mensagens_chat_destinatarioId_lida_idx" ON "mensagens_chat"("destinatarioId", "lida");

-- CreateIndex
CREATE INDEX "solicitacoes_material_andamento_idx" ON "solicitacoes_material"("andamento");

-- CreateIndex
CREATE INDEX "solicitacoes_material_dataNecessidade_idx" ON "solicitacoes_material"("dataNecessidade");

-- CreateIndex
CREATE INDEX "visualizacoes_solicitacao_usuarioId_idx" ON "visualizacoes_solicitacao"("usuarioId");

-- CreateIndex
CREATE INDEX "visualizacoes_solicitacao_solicitacaoId_idx" ON "visualizacoes_solicitacao"("solicitacaoId");

-- CreateIndex
CREATE UNIQUE INDEX "visualizacoes_solicitacao_usuarioId_solicitacaoId_key" ON "visualizacoes_solicitacao"("usuarioId", "solicitacaoId");

-- CreateIndex
CREATE INDEX "logs_edicao_solicitacao_solicitacaoId_idx" ON "logs_edicao_solicitacao"("solicitacaoId");

-- CreateIndex
CREATE INDEX "movimentacoes_estoque_materialOrigemId_idx" ON "movimentacoes_estoque"("materialOrigemId");

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_remetenteId_fkey" FOREIGN KEY ("remetenteId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mensagens_chat" ADD CONSTRAINT "mensagens_chat_destinatarioId_fkey" FOREIGN KEY ("destinatarioId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ordem_compra_itens" ADD CONSTRAINT "ordem_compra_itens_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_materialOrigemId_fkey" FOREIGN KEY ("materialOrigemId") REFERENCES "materiais"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "solicitacoes_material" ADD CONSTRAINT "solicitacoes_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "solicitacoes_material" ADD CONSTRAINT "solicitacoes_material_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "visualizacoes_solicitacao" ADD CONSTRAINT "visualizacoes_solicitacao_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "visualizacoes_solicitacao" ADD CONSTRAINT "visualizacoes_solicitacao_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "logs_edicao_solicitacao" ADD CONSTRAINT "logs_edicao_solicitacao_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "logs_edicao_solicitacao" ADD CONSTRAINT "logs_edicao_solicitacao_editorId_fkey" FOREIGN KEY ("editorId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
