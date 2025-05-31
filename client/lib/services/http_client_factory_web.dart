// client/lib/services/http_client_factory_web.dart
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;

http.Client createHttpClient() {
  final client = BrowserClient();
  client.withCredentials = true;
  debugPrint("ApiService: Using BrowserClient with withCredentials=true for web");
  return client;
}