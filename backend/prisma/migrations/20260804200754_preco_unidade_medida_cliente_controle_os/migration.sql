-- AlterTable
ALTER TABLE "fornecedor_materiais" ADD COLUMN     "precoUnidadeMedida" DECIMAL(15,6);

-- AlterTable
ALTER TABLE "historico_precos_material" ADD COLUMN     "qtdUnidade" DECIMAL(15,6);

-- AlterTable
ALTER TABLE "relacoes_os" ADD COLUMN     "cliente" TEXT;
