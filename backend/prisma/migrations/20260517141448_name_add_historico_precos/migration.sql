-- AlterTable
ALTER TABLE "materiais" ADD COLUMN     "ultimoValorPagoM2" DECIMAL(10,2);

-- CreateTable
CREATE TABLE "historico_precos_material" (
    "id" SERIAL NOT NULL,
    "materialId" INTEGER NOT NULL,
    "ordemCompraId" INTEGER NOT NULL,
    "fornecedorId" INTEGER NOT NULL,
    "precoUnitario" DECIMAL(10,2) NOT NULL,
    "precoM2" DECIMAL(10,2),
    "quantidade" DECIMAL(10,3) NOT NULL,
    "criadoEm" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "historico_precos_material_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "materiais"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_ordemCompraId_fkey" FOREIGN KEY ("ordemCompraId") REFERENCES "ordens_compra"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "historico_precos_material" ADD CONSTRAINT "historico_precos_material_fornecedorId_fkey" FOREIGN KEY ("fornecedorId") REFERENCES "fornecedores"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
