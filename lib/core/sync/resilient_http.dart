import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP for the company server that keeps working when the phone's DNS
/// cannot find the server name ("Failed host lookup" while other apps have
/// internet, seen on some mobile networks). The normal lookup is tried first;
/// if it fails, the address is asked from DNS-over-HTTPS (Cloudflare and
/// Google, reached by IP so they need no DNS themselves) and the connection
/// goes to that address with the real server name for TLS.
class ResilientHttp {
  static final Map<String, InternetAddress> _dohCache = {};

  /// Whether the last lookup of [host] needed the fallback.
  static final Set<String> usedFallback = {};

  static http.Client create() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..connectionFactory = _connect;
    return IOClient(io);
  }

  static Future<ConnectionTask<Socket>> _connect(Uri uri, String? proxyHost, int? proxyPort) async {
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? (uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80));
    final address = await resolve(host);
    final task = await Socket.startConnect(address, port);
    if (uri.scheme != 'https' || proxyHost != null) return task;
    return ConnectionTask.fromSocket(
      task.socket.then((socket) => SecureSocket.secure(socket, host: uri.host)),
      task.cancel,
    );
  }

  /// The phone's own lookup, then DNS-over-HTTPS.
  static Future<InternetAddress> resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    try {
      final found = await InternetAddress.lookup(host).timeout(const Duration(seconds: 10));
      if (found.isNotEmpty) {
        usedFallback.remove(host);
        return found.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => found.first);
      }
    } catch (_) {
      // Fall through to DNS-over-HTTPS.
    }
    final doh = await dohLookup(host);
    if (doh != null) {
      usedFallback.add(host);
      return doh;
    }
    throw SocketException('Failed host lookup: $host');
  }

  static Future<InternetAddress?> dohLookup(String host) async {
    final cached = _dohCache[host];
    if (cached != null) return cached;
    const resolvers = ['https://1.1.1.1/dns-query', 'https://8.8.8.8/resolve', 'https://1.0.0.1/dns-query'];
    for (final resolver in resolvers) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.getUrl(Uri.parse('$resolver?name=${Uri.encodeQueryComponent(host)}&type=A'));
        req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
        final res = await req.close().timeout(const Duration(seconds: 10));
        final body = await res.transform(utf8.decoder).join();
        final answers = (jsonDecode(body) as Map)['Answer'];
        if (answers is List) {
          for (final a in answers) {
            if (a is Map && a['type'] == 1) {
              final ip = InternetAddress.tryParse('${a['data']}');
              if (ip != null) return _dohCache[host] = ip;
            }
          }
        }
      } catch (_) {
        // Next resolver.
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }
}
