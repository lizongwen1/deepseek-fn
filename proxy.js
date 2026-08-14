#!/usr/bin/env node
'use strict';
// 反向代理：监听 0.0.0.0:3081 -> 转发 dsh web 127.0.0.1:3080
// 解决的问题：
//  1) dsh web 响应头带 X-Frame-Options / CSP frame-ancestors，飞牛 iframe 被浏览器静默拦截 -> 白屏
//     这里直接删除这些响应头，允许 iframe 嵌入。
//  2) dsh web 前端用到 crypto.randomUUID / AbortSignal.timeout / AbortSignal.any，
//     而飞牛内置 webview（及部分旧浏览器 / 非安全上下文的 http://LAN）没有这些 API -> 报错。
//     这里在 HTML 的 </head> 前注入 polyfill，提前挂上全局实现。
//  3) dsh web 的 /api 有 browser-trust 围栏（防 DNS 重绑定），host.* 特权 RPC 默认只信任
//     127.0.0.1:<port>。浏览器/fnOS 经 LAN IP 访问时 Host 头带 LAN IP -> 被拒 403。
//     代理把转发的 Host/Origin 改写成 127.0.0.1:<port>（代理本就在本机连它，合法 loopback）。
//  4) 同时支持 WebSocket 升级（agent 流式输出用），原样 TCP 隧道转发。

const http = require('http');
const net = require('net');

const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = 3080;
const LISTEN_PORT = 3081;
const MAX_RETRY = 50; // 启动竞态：dsh 未就绪时最多重试 ~10s

const POLYFILL = `<script>(function(){
  try {
    if (!globalThis.crypto) globalThis.crypto = {};
    if (typeof globalThis.crypto.getRandomValues !== 'function') {
      globalThis.crypto.getRandomValues = function(arr){
        for (var i=0;i<arr.length;i++) arr[i] = Math.floor(Math.random()*256);
        return arr;
      };
    }
    if (typeof globalThis.crypto.randomUUID !== 'function') {
      globalThis.crypto.randomUUID = function(){
        var b = new Uint8Array(16);
        globalThis.crypto.getRandomValues(b);
        b[6] = (b[6] & 0x0f) | 0x40;
        b[8] = (b[8] & 0x3f) | 0x80;
        var h = [];
        for (var i=0;i<16;i++) h.push((b[i]+256).toString(16).slice(1));
        return h.slice(0,4).join('')+'-'+h.slice(4,6).join('')+'-'+h.slice(6,8).join('')+'-'+h.slice(8,10).join('')+'-'+h.slice(10,16).join('');
      };
    }
    if (typeof globalThis.AbortSignal !== 'function' && !globalThis.AbortSignal) {
      // 极旧环境连 AbortSignal 构造函数都没有
      globalThis.AbortSignal = function(){};
    }
    if (typeof globalThis.AbortSignal.timeout !== 'function') {
      globalThis.AbortSignal.timeout = function(ms){
        var ctrl = new AbortController();
        var reason = (typeof DOMException !== 'undefined')
          ? new DOMException('Signal timed out', 'TimeoutError')
          : (function(){ var e = new Error('Signal timed out'); e.name = 'TimeoutError'; return e; })();
        var id = setTimeout(function(){ ctrl.abort(reason); }, ms);
        ctrl.signal.addEventListener('abort', function(){ clearTimeout(id); });
        return ctrl.signal;
      };
    }
    if (typeof globalThis.AbortSignal.any !== 'function') {
      globalThis.AbortSignal.any = function(signals){
        var controller = new AbortController();
        var aborted = false;
        var abortOne = function(reason) {
          if (aborted) return;
          aborted = true;
          controller.abort(reason);
        };
        for (var i = 0; i < signals.length; i++) {
          (function(s){
            if (s.aborted) { abortOne(s.reason); return; }
            s.addEventListener('abort', function(){ abortOne(s.reason); }, { once: true });
          })(signals[i]);
        }
        return controller.signal;
      };
    }
  } catch (e) { /* 忽略 polyfill 异常，交由页面自身处理 */ }
})();</script>`;

function sendProxy(req, res, attempt) {
  // 强制 dsh web 返回未压缩内容，便于 HTML 注入
  const headers = Object.assign({}, req.headers);
  headers['accept-encoding'] = 'identity';

  // 关键修复：把 Host/Origin 改写成 loopback，让 dsh 的 browser-trust 围栏放行。
  // dsh web 的 /api 围栏默认只信任 127.0.0.1(<port>)，浏览器/fnOS 经 LAN IP 访问时
  // Host 头带的是 LAN IP，不在受信列表 -> host.listDirectory 等特权 RPC 返回 403。
  // 代理本身就在本机连 127.0.0.1:TARGET_PORT，改写 Host 为 loopback 是合法且必要的。
  headers['host'] = TARGET_HOST + ':' + TARGET_PORT;
  if (headers['origin']) headers['origin'] = 'http://' + TARGET_HOST + ':' + TARGET_PORT;
  if (headers['referer']) headers['referer'] = 'http://' + TARGET_HOST + ':' + TARGET_PORT + '/';

  const options = {
    method: req.method,
    headers: headers,
    hostname: TARGET_HOST,
    port: TARGET_PORT,
    path: req.url,
  };

  const proxy = http.request(options, function (pres) {
    // 移除会阻止 iframe 嵌入的响应头
    const outHeaders = Object.assign({}, pres.headers);
    delete outHeaders['x-frame-options'];
    delete outHeaders['content-security-policy'];

    // 注入 CORS 头，允许浏览器跨域调用 dsh API（修复 /api/* 403）
    outHeaders['access-control-allow-origin'] = req.headers['origin'] || '*';
    outHeaders['access-control-allow-credentials'] = 'true';

    // 防御：若 dsh 返回指向 127.0.0.1 的重定向，改写为客户端实际访问的 host
    if (outHeaders['location'] && /127\.0\.0\.1/.test(outHeaders['location'])) {
      try {
        const u = new URL(outHeaders['location']);
        const clientHost = req.headers['host'] || (TARGET_HOST + ':' + LISTEN_PORT);
        outHeaders['location'] = u.protocol + '//' + clientHost + u.pathname + u.search + u.hash;
      } catch (e) { /* 忽略解析失败 */ }
    }

    const ct = pres.headers['content-type'] || '';
    if (ct.indexOf('text/html') !== -1) {
      let body = '';
      pres.setEncoding('utf8');
      pres.on('data', function (d) { body += d; });
      pres.on('end', function () {
        let out = body;
        if (/<\/head>/i.test(out)) {
          out = out.replace(/<\/head>/i, POLYFILL + '</head>');
        } else if (/<head>/i.test(out)) {
          out = out.replace(/<head>/i, '<head>' + POLYFILL);
        } else {
          out = POLYFILL + out;
        }
        outHeaders['content-length'] = Buffer.byteLength(out);
        delete outHeaders['content-encoding'];
        res.writeHead(pres.statusCode, outHeaders);
        res.end(out);
      });
    } else {
      res.writeHead(pres.statusCode, outHeaders);
      pres.pipe(res);
    }
  });

  proxy.on('error', function (err) {
    // 启动竞态：dsh 还没绑好端口时，对幂等请求重试
    if (err.code === 'ECONNREFUSED' && attempt < MAX_RETRY &&
        (req.method === 'GET' || req.method === 'HEAD')) {
      setTimeout(function () { sendProxy(req, res, attempt + 1); }, 200);
      return;
    }
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Bad gateway: ' + err.message);
    } else {
      res.destroy();
    }
  });

  req.pipe(proxy);
}

const server = http.createServer(function (req, res) {
  // CORS：处理 OPTIONS 预检请求
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': req.headers['origin'] || '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Max-Age': '86400',
    });
    res.end();
    return;
  }
  sendProxy(req, res, 0);
});

// WebSocket / 其他协议升级：原样 TCP 隧道转发
server.on('upgrade', function (req, clientSocket, head) {
  const targetSocket = net.connect(TARGET_PORT, TARGET_HOST, function () {
    let reqLine = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
    for (const k in req.headers) {
      reqLine += k + ': ' + req.headers[k] + '\r\n';
    }
    reqLine += '\r\n';
    targetSocket.write(reqLine);
    if (head && head.length) targetSocket.write(head);
    targetSocket.pipe(clientSocket);
    clientSocket.pipe(targetSocket);
  });
  targetSocket.on('error', function () { clientSocket.destroy(); });
  clientSocket.on('error', function () { targetSocket.destroy(); });
});

server.listen(LISTEN_PORT, '0.0.0.0', function () {
  console.log('[proxy] listening on 0.0.0.0:' + LISTEN_PORT + ' -> ' + TARGET_HOST + ':' + TARGET_PORT);
});
