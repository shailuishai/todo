// client/lib/services/http_client_factory_io.dart
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

http.Client createHttpClient() {
  debugPrint("ApiService: Using default http.Client for non-web platform");
  return http.Client();
}