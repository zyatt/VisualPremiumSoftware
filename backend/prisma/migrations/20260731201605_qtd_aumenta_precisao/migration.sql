-- AlterTable
ALTER TABLE "adicionais_solicitacao_material" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "baixas_producao" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "entradas_pendentes" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "estoque_producao" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "quantidadePendente" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "historico_precos_material" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "itens_solicitacao_material" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "materiais" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "estoqueMinimo" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "movimentacoes_estoque" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "movimentacoes_producao" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_itens" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "orcamento_venda_itens" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "ordem_compra_itens" ALTER COLUMN "quantidade" SET DATA TYPE DECIMAL(15,6);

-- AlterTable
ALTER TABLE "solicitacoes_producao" ALTER COLUMN "quantidadeReservada" SET DATA TYPE DECIMAL(15,6),
ALTER COLUMN "quantidadeUsada" SET DATA TYPE DECIMAL(15,6);
