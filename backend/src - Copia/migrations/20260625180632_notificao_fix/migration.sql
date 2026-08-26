-- CreateTable
CREATE TABLE "visualizacoes_solicitacao" (
    "id" SERIAL NOT NULL,
    "usuarioId" INTEGER NOT NULL,
    "solicitacaoId" INTEGER NOT NULL,
    "visualizadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "visualizacoes_solicitacao_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "visualizacoes_solicitacao_usuarioId_idx" ON "visualizacoes_solicitacao"("usuarioId");

-- CreateIndex
CREATE INDEX "visualizacoes_solicitacao_solicitacaoId_idx" ON "visualizacoes_solicitacao"("solicitacaoId");

-- CreateIndex
CREATE UNIQUE INDEX "visualizacoes_solicitacao_usuarioId_solicitacaoId_key" ON "visualizacoes_solicitacao"("usuarioId", "solicitacaoId");

-- AddForeignKey
ALTER TABLE "visualizacoes_solicitacao" ADD CONSTRAINT "visualizacoes_solicitacao_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "visualizacoes_solicitacao" ADD CONSTRAINT "visualizacoes_solicitacao_solicitacaoId_fkey" FOREIGN KEY ("solicitacaoId") REFERENCES "solicitacoes_material"("id") ON DELETE CASCADE ON UPDATE CASCADE;
