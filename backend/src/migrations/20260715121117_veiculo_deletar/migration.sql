-- DropForeignKey
ALTER TABLE "manutencoes_veiculo" DROP CONSTRAINT "manutencoes_veiculo_veiculoId_fkey";

-- AddForeignKey
ALTER TABLE "manutencoes_veiculo" ADD CONSTRAINT "manutencoes_veiculo_veiculoId_fkey" FOREIGN KEY ("veiculoId") REFERENCES "veiculos"("id") ON DELETE CASCADE ON UPDATE CASCADE;
