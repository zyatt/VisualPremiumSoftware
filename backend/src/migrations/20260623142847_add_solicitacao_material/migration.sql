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
    "usuarioId" INTEGER NOT NULL,
    "usuarioNome" TEXT NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizadoEm" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "solicitacoes_material_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "solicitacoes_material_andamento_idx" ON "solicitacoes_material"("andamento");

-- CreateIndex
CREATE INDEX "solicitacoes_material_dataNecessidade_idx" ON "solicitacoes_material"("dataNecessidade");

-- AddForeignKey
ALTER TABLE "solicitacoes_material" ADD CONSTRAINT "solicitacoes_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "solicitacoes_material" ADD CONSTRAINT "solicitacoes_material_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
