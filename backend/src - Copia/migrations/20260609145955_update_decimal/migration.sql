/*
  Warnings:

  - You are about to alter the column `precoM2` on the `movimentacoes_estoque` table. The data in that column could be lost. The data in that column will be cast from `Decimal(65,30)` to `Decimal(15,5)`.

*/
-- AlterTable
ALTER TABLE "estoque_especificos" ALTER COLUMN "ultimoValorPago" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "ultimoValorPagoM2" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "fornecedor_materiais" ALTER COLUMN "preco" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoMetroQuadrado" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "historico_precos_material" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "materiais" ALTER COLUMN "valor" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "valorMetroQuadrado" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "ultimoValorPago" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "ultimoValorPagoM2" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "movimentacoes_estoque" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "orcamento_itens" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoM2" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "ordem_compra_itens" ALTER COLUMN "precoUnitario" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoMetroQuadrado" SET DATA TYPE DECIMAL(15,5),
ALTER COLUMN "precoTotal" SET DATA TYPE DECIMAL(15,5);

-- AlterTable
ALTER TABLE "ordens_compra" ALTER COLUMN "valorTotal" SET DATA TYPE DECIMAL(15,5);
