// Minimal static file server for the built web app.
//
// `flutter run -d web-server` injects a debug client (DWDS) that currently
// throws before the app mounts, so for browser testing we serve the output of
// `flutter build web` directly. Web Bluetooth requires a secure context;
// localhost counts, so http://localhost:<port> is fine.
//
// Usage: dart run tool/serve_web.dart [port] [rootDir]
import 'dart:io';

const _mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
};

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 8080;
  final root = Directory(args.length > 1 ? args[1] : 'build/web').absolute;
  if (!root.existsSync()) {
    stderr.writeln('No build found at ${root.path} — run `flutter build web` first.');
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving ${root.path} on http://localhost:$port');

  await for (final req in server) {
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path == '/' || path.isEmpty) path = '/index.html';
      var file = File('${root.path}$path');
      // Single-page fallback for unknown paths without an extension.
      if (!file.existsSync() && !path.contains('.')) {
        file = File('${root.path}/index.html');
      }
      if (!file.existsSync()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      final dot = file.path.lastIndexOf('.');
      final ext = dot == -1 ? '' : file.path.substring(dot).toLowerCase();
      req.response.headers.contentType =
          ContentType.parse(_mime[ext] ?? 'application/octet-stream');
      // Never cache: rebuilds must be picked up on reload.
      req.response.headers.set('Cache-Control', 'no-store');
      await req.response.addStream(file.openRead());
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {/* client gone */}
    }
  }
}
