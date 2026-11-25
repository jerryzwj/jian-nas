const express = require('express');
const DdnsController = require('./ddnsController');
const { authenticateJWT, requireSuperAdmin } = require('../../../middleware/authMiddleware');

const router = express.Router();
const controller = new DdnsController();

router.get('/status', authenticateJWT, controller.getStatus.bind(controller));
router.post('/save', authenticateJWT, requireSuperAdmin, controller.save.bind(controller));
router.post('/disable', authenticateJWT, requireSuperAdmin, controller.disable.bind(controller));
router.post('/run', authenticateJWT, requireSuperAdmin, controller.runNow.bind(controller));

module.exports = router;
