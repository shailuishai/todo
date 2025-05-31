// lib/widgets/CustomInputField.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomInputField extends StatefulWidget {
  final String label;
  final bool isPassword;
  final String? Function(String?)? validator;
  final TextEditingController? controller;
  final String? initialValue; // <<< ДОБАВЛЕНО
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;
  final AutovalidateMode autovalidateMode;
  final String? hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final bool readOnly; // <<< ДОБАВЛЕНО
  final bool? enabled; // <<< ДОБАВЛЕНО (может быть bool?, чтобы не переопределять дефолтное поведение TextFormField)
  final bool autofocus; // <<< ДОБАВЛЕНО

  const CustomInputField({
    super.key,
    required this.label,
    this.isPassword = false,
    this.validator,
    this.controller,
    this.initialValue, // <<< ДОБАВЛЕНО
    this.textInputAction,
    this.focusNode,
    this.onFieldSubmitted,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.readOnly = false, // <<< ДОБАВЛЕНО (значение по умолчанию)
    this.enabled,         // <<< ДОБАВЛЕНО
    this.autofocus = false, // <<< ДОБАВЛЕНО (значение по умолчанию)
  });

  @override
  State<CustomInputField> createState() => _CustomInputFieldState();
}

class _CustomInputFieldState extends State<CustomInputField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _obscureText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue); // <<< УЧИТЫВАЕМ initialValue
    _focusNode = widget.focusNode ?? FocusNode();
    if (widget.isPassword) {
      _obscureText = true;
    }
  }

  @override
  void didUpdateWidget(CustomInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если контроллер не предоставлен извне и initialValue изменился, обновляем текст
    if (widget.controller == null && widget.initialValue != oldWidget.initialValue) {
      // Проверяем, что текущее значение в контроллере отличается от нового initialValue,
      // чтобы не перезаписывать то, что пользователь мог уже ввести, если initialValue
      // меняется по другим причинам (хотя это редкий кейс для initialValue).
      // Более безопасный подход - избегать изменения initialValue после первого рендера,
      // а управлять значением через controller.
      if (_controller.text != widget.initialValue) {
        _controller.text = widget.initialValue ?? '';
      }
    }
    // Если используется внешний контроллер, его обновление - ответственность родительского виджета.
  }


  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      obscureText: _obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly, // <<< ИСПОЛЬЗУЕМ
      enabled: widget.enabled,   // <<< ИСПОЛЬЗУЕМ
      autofocus: widget.autofocus, // <<< ИСПОЛЬЗУЕМ
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w500,
        fontSize: 15,
        color: widget.enabled == false // Если поле отключено, делаем текст менее заметным
            ? theme.colorScheme.onSurface.withOpacity(0.6)
            : theme.colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.isPassword
            ? IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          onPressed: _togglePasswordVisibility,
        )
            : null,
        // Стиль для отключенного состояния
        disabledBorder: theme.inputDecorationTheme.disabledBorder ??
            theme.inputDecorationTheme.enabledBorder?.copyWith(
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withOpacity(0.38), // Стандартный цвет для disabled
              ),
            ),
        fillColor: widget.enabled == false
            ? theme.colorScheme.onSurface.withOpacity(0.04) // Другой fillColor для disabled
            : theme.inputDecorationTheme.fillColor,
      ),
    );
  }
}