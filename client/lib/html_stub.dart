// lib/html_stub.dart

// Этот файл-заглушка используется, когда dart:html недоступен (например, на мобильных платформах).
// Он должен экспортировать те же имена, что и dart:html, которые используются в вашем коде,
// но с реализацией, которая не вызывает ошибок.

import 'dart:async';

class _LocationStub {
  String get href => ''; // Пустая строка или осмысленное значение по умолчанию
// Можно добавить другие геттеры/сеттеры, если они используются из location, например:
// String get origin => '';
// String get pathname => '';
// void assign(String url) {}
// void reload() {}
}

class _HistoryStub {
  void replaceState(dynamic data, String title, String? url) {
    // Ничего не делаем
  }
// Можно добавить другие методы, если они используются из history, например:
// void pushState(dynamic data, String title, String? url) {}
// void back() {}
// void forward() {}
// int get length => 0;
}

// <<< НОВАЯ ЗАГЛУШКА ДЛЯ NAVIGATOR >>>
class _NavigatorStub {
  String get userAgent => 'DartVM (UnknownOS; Stub)'; // Заглушка для userAgent
// Можно добавить другие поля/методы navigator, если они используются, например:
// String get platform => 'Unknown';
// String get appVersion => '0.0 (Stub)';
// bool get cookieEnabled => false;
}
// <<< КОНЕЦ НОВОЙ ЗАГЛУШКИ >>>

class _WindowStub {
  // Используем late для инициализации контроллера при первом обращении,
  // чтобы избежать проблем с hot reload, если он создается слишком рано.
  // Или оставляем как было, если проблем нет.
  late final StreamController<dynamic> _onPopStateController = StreamController.broadcast(sync: true);
  Stream<dynamic> get onPopState => _onPopStateController.stream;

  final _LocationStub location = _LocationStub();
  final _HistoryStub history = _HistoryStub();
  final _NavigatorStub navigator = _NavigatorStub(); // <<< ДОБАВЛЕНО ПОЛЕ NAVIGATOR >>>

  // Пример других методов, если они используются:
  // void open(String url, String name, [String? options]) { /* ... */ }
  // dynamic alert(String message) { /* ... */ }
  // dynamic confirm(String message) { /* ... */ }
  // Future<dynamic> postMessage(dynamic message, String targetOrigin, [List<dynamic>? transfer]) async { /* ... */ }

  // Метод close теперь не нужен, т.к. StreamController будет закрыт при dispose объекта _WindowStub,
  // но т.к. window - глобальная переменная, она не будет диспозиться.
  // Если _onPopStateController создается с sync: true, это может помочь избежать некоторых проблем.
  // Оставим close, если он где-то вызывается, но обычно для глобальных объектов это не делается.
  void close() {
    if (!_onPopStateController.isClosed) {
      _onPopStateController.close();
    }
  }
}

// Экспортируем экземпляр заглушки как 'window'
final _WindowStub window = _WindowStub();

// Пример заглушки для Document, если понадобится
// class _ElementStub {
//   // ...
// }
// class _DocumentStub {
//   _ElementStub? get documentElement => null;
//   _ElementStub? get body => null;
//   _ElementStub? get head => null;
//   // ...
// }
// final _DocumentStub document = _DocumentStub();

// Пример для Storage (localStorage, sessionStorage)
// class _StorageStub implements Storage {
//   final Map<String, String> _data = {};
//   @override
//   String? getItem(String key) => _data[key];
//   @override
//   void setItem(String key, String value) => _data[key] = value;
//   @override
//   void removeItem(String key) => _data.remove(key);
//   @override
//   void clear() => _data.clear();
//   @override
//   int get length => _data.length;
//   @override
//   String? key(int index) => _data.keys.elementAtOrNull(index);
//   // Эти методы могут быть не нужны для заглушки, если не используются:
//   @override
//   bool containsKey(String? key) => _data.containsKey(key);
//   @override
//   void add(Map<String, String> other) => _data.addAll(other);
//   @override
//   void addAll(Map<String, String> other) => _data.addAll(other);
//   @override
//   Iterable<String> get keys => _data.keys;
//   // ... и т.д.
// }
// final Storage localStorage = _StorageStub();
// final Storage sessionStorage = _StorageStub();

// Заглушка для dart:html Storage интерфейса (если используется)
// abstract class Storage {
//   String? getItem(String key);
//   void setItem(String key, String value);
//   void removeItem(String key);
//   void clear();
//   int get length;
//   String? key(int index);
// }