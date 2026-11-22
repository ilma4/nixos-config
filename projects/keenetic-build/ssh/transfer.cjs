const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');

function serve(filename, port) {
  const [archive, listenAddress, routerAddress] = process.argv.slice(2);
  if (!archive || !net.isIPv4(listenAddress) || !net.isIPv4(routerAddress) || process.argv.length !== 5) {
    console.error('Usage: node ' + process.argv[1] + ' <archive> <listen-ipv4> <router-ipv4>');
    process.exitCode = 2;
    return;
  }

  const info = fs.statSync(archive);
  if (!info.isFile()) {
    throw new Error('Expected a payload archive file');
  }
  const server = http.createServer((request, response) => {
    if (request.socket.remoteAddress !== routerAddress ||
        request.url !== '/' + filename || request.method !== 'GET') {
      response.writeHead(404).end();
      return;
    }

    const stream = fs.createReadStream(archive);
    stream.on('open', () => {
      response.writeHead(200, { 'Content-Length': info.size });
      stream.pipe(response);
    });
    stream.on('error', () => {
      if (response.headersSent) {
        response.destroy();
      } else {
        response.writeHead(500).end();
      }
    });
    response.on('close', () => stream.destroy());
  });
  server.listen(port, listenAddress);
}

module.exports = serve;
if (require.main === module) {
  serve('ssh-payload.tar.gz', 18229);
}
