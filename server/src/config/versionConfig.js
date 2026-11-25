/**
 * 服务端版本号（整数），用于登录等接口返回，便于客户端做版本判断
 */
const SERVER_VERSION = 12;
const UPDATE_FEED_URL = 'http://127.0.0.1:1/package/';
const HOME_PAGE_URL = 'http://127.0.0.1:1';
module.exports = {
  SERVER_VERSION,
  UPDATE_FEED_URL,
  HOME_PAGE_URL,
};
