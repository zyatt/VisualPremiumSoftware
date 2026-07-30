const router = require('express').Router();

const ctrl = require('../controllers/estoqueProducao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

// Mesmos papéis usados em estoque.routes.js — ajuste se necessário.
// PRODUCAO1/PRODUCAO2 substituem o antigo cargo único PRODUCAO: cada um só
// enxerga/opera a própria linha (restrição aplicada no controller, a
// partir de req.usuario.role — ver _resolverProducao).
const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA', 'PRODUCAO1', 'PRODUCAO2'];
const ESCRITA = ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO1', 'PRODUCAO2'];
// Transferir material de uma linha de produção para a outra — só ADMIN e
// GERENTE podem mover saldo entre as duas linhas (nem COMPRAS, que só tem
// leitura combinada, nem PRODUCAO1/PRODUCAO2, que só operam a própria linha).
const TRANSFERENCIA_LINHA = ['ADMIN', 'GERENTE'];

// Transferência do estoque normal -> estoque de produção
// (chamada pela página de Controle de Estoque)
router.post('/transferir', authMiddleware, roleMiddleware(ESCRITA), ctrl.transferir);

// Devolução do estoque de produção -> estoque normal (operação inversa)
router.post('/devolver', authMiddleware, roleMiddleware(ESCRITA), ctrl.devolver);

// Transferência de material entre as duas linhas de produção (1 <-> 2)
router.post('/transferir-linha', authMiddleware, roleMiddleware(TRANSFERENCIA_LINHA), ctrl.transferirEntreLinhas);

// Estoque de produção (saldo atual)
router.get('/', authMiddleware, roleMiddleware(LEITURA), ctrl.listarEstoque);

// Baixa de material do estoque de produção para uma OS
router.post('/baixas', authMiddleware, roleMiddleware(ESCRITA), ctrl.darBaixa);

// Histórico (transferências recebidas + baixas por OS)
router.get('/historico', authMiddleware, roleMiddleware(LEITURA), ctrl.listarHistorico);

// Excluir um registro do histórico (apenas remove o registro — não altera saldo)
router.delete('/historico/:id', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE']), ctrl.excluirHistorico);

module.exports = router;