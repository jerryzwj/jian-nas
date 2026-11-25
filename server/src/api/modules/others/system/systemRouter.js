const express = require('express');
const SystemController = require('./systemController');

const router = express.Router();
const controller = new SystemController();

// 登录页要用，故意不鉴权：只返回地址与端口
router.get('/lan-addresses', controller.lanAddresses.bind(controller));

module.exports = router;
