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
ALTER TABLE "estoque_producao" ADD CONSTRAINT "estoque_producao_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "movimentacoes_producao" ADD CONSTRAINT "movimentacoes_producao_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
