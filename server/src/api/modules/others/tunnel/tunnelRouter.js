const express = require('express');
const TunnelController = require('./tunnelController');
const { authenticateJWT, requireSuperAdmin } = require('../../../middleware/authMiddleware');

const router = express.Router();
const controller = new TunnelController();

router.get('/status', authenticateJWT, controller.getStatus.bind(controller));
router.post('/checkSubdomain', authenticateJWT, controller.checkSubdomain.bind(controller));
router.post('/enable', authenticateJWT, requireSuperAdmin, controller.enable.bind(controller));
router.post('/disable', authenticateJWT, requireSuperAdmin, controller.disable.bind(controller));

module.exports = router;
