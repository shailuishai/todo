// lib/core/constants/app_strings.dart (Пример, можно расширять)
class AppStrings {
  // AuthScreen
  static const String loginTitle = 'Войти';
  static const String registerTitle = 'Зарегистрироваться';
  static const String createAccountLink = 'Создать аккаунт →';
  static const String alreadyHaveAccountLink = 'Уже есть аккаунт? Войти →';
  static const String loginVia = 'Вход через'; // Для SnackBar

  // LoginForm
  static const String emailOrLoginLabel = 'Email или Логин';
  static const String passwordLabel = 'Пароль';
  static const String emailRequiredError = 'Введите email';
  static const String invalidEmailError = 'Некорректный email';
  static const String passwordRequiredError = 'Введите пароль';
  static const String passwordMinLengthError = 'Минимум 6 символов';
  static const String passwordComplexityError = 'Пароль должен содержать буквы и цифры';

  // RegisterForm
  static const String usernameLabel = 'Логин'; // Было 'Логин' в коде, но 'Имя' в validator
  static const String usernameRequiredError = 'Введите логин';
  static const String emailLabel = 'Email';
  static const String confirmPasswordLabel = 'Подтвердите пароль';
  static const String confirmPasswordRequiredError = 'Подтвердите пароль';
  static const String passwordsDoNotMatchError = 'Пароли не совпадают';
}