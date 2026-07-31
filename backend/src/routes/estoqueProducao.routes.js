const router = require('express').Router();

const ctrl = require('../controllers/estoqueProducao.controller');
const { authMiddleware, roleMiddleware } = require('../middlewares/auth.middleware');

const LEITURA = ['ADMIN', 'GERENTE', 'COMPRAS', 'ORCAMENTISTA', 'PRODUCAO1', 'PRODUCAO2'];
const ESCRITA = ['ADMIN', 'GERENTE', 'COMPRAS', 'PRODUCAO1', 'PRODUCAO2'];

const TRANSFERENCIA_LINHA = ['ADMIN', 'GERENTE'];

router.post('/transferir', authMiddleware, roleMiddleware(ESCRITA), ctrl.transferir);

router.post('/devolver', authMiddleware, roleMiddleware(ESCRITA), ctrl.devolver);

router.post('/transferir-linha', authMiddleware, roleMiddleware(TRANSFERENCIA_LINHA), ctrl.transferirEntreLinhas);

router.get('/', authMiddleware, roleMiddleware(LEITURA), ctrl.listarEstoque);

router.post('/baixas', authMiddleware, roleMiddleware(ESCRITA), ctrl.darBaixa);

router.get('/historico', authMiddleware, roleMiddleware(LEITURA), ctrl.listarHistorico);

router.delete('/historico/:id', authMiddleware, roleMiddleware(['ADMIN', 'GERENTE']), ctrl.excluirHistorico);

router.get('/pendentes', authMiddleware, roleMiddleware(LEITURA), ctrl.listarPendentes);
router.get('/pendentes/contador', authMiddleware, roleMiddleware(LEITURA), ctrl.contarPendentes);
router.post('/pendentes/:id/confirmar', authMiddleware, roleMiddleware(ESCRITA), ctrl.confirmarPendente);
router.post('/pendentes/:id/recusar', authMiddleware, roleMiddleware(ESCRITA), ctrl.recusarPendente);

module.exports = router;