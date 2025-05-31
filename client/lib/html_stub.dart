// lib/html_stub.dart

// Этот файл-заглушка используется, когда dart:html недоступен (например, на мобильных платформах).
// Он должен экспортировать те же имена, что и dart:html, которые используются в вашем коде,
// но с реализацией, которая не вызывает ошибок.

// Заглушка для html.window
// Нам нужны поля history, onPopState, location
// В реальных не-веб сценариях эти методы не будут вызываться благодаря проверке kIsWeb.
// Но для компиляции они должны существовать.

import 'dart:async';

class _LocationStub {
  String get href => ''; // Пустая строка или осмысленное значение по умолчанию
}

class _HistoryStub {
  void replaceState(dynamic data, String title, String? url) {
    // Ничего не делаем
  }
}

class _WindowStub {
  StreamController<dynamic> _onPopStateController = StreamController.broadcast();
  Stream<dynamic> get onPopState => _onPopStateController.stream;

  final _LocationStub location = _LocationStub();
  final _HistoryStub history = _HistoryStub();

  // Можно добавить другие методы/поля, если они используются, например:
  // void open(String url, String name, [String? options]) { /* ... */ }

  void close() { // Метод для закрытия StreamController, если он больше не нужен
    _onPopStateController.close();
  }
}

// Экспортируем экземпляр заглушки как 'window'
final _WindowStub window = _WindowStub();

// Если ты используешь другие части dart:html, их тоже нужно будет здесь "заглушить".
// Например, если бы ты использовал html.document:
// class _DocumentStub { ... }
// final _DocumentStub document = _DocumentStub();