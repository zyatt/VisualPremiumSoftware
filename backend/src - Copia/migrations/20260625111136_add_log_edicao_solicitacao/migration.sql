-- AlterTable
ALTER TABLE "solicitacoes_material" ADD COLUMN     "imagemUrl" TEXT;

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
CREATE INDEX "logs_edicao_solicitacao_solicitacaoId_idx" ON "logs_edicao_solicitacao"("solicitacaoId");

-- AddForeignKey
ALTER TABLE "logs_edicao_solicitacao" ADD CONSTRAINT "logs_edicao_solicitacao_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "logs_edicao_solicitacao" ADD CONSTRAINT "logs_edicao_solicitacao_editorId_fkey" FOREIGN KEY ("editorId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
