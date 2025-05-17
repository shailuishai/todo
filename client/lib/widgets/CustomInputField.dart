// lib/widgets/CustomInputField.dart
import 'package:flutter/material.dart';

class CustomInputField extends StatefulWidget {
  final String label;
  final bool isPassword;
  final String? Function(String?)? validator;
  final TextEditingController? controller;
  final Key? formFieldKey;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;
  final AutovalidateMode autovalidateMode;

  const CustomInputField({
    super.key,
    required this.label,
    this.isPassword = false,
    required this.validator,
    this.controller,
    this.formFieldKey,
    this.textInputAction,
    this.focusNode,
    this.onFieldSubmitted,
    this.autovalidateMode = AutovalidateMode.disabled,
  });

  @override
  State<CustomInputField> createState() => _CustomInputFieldState();
}

class _CustomInputFieldState extends State<CustomInputField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _isFocused = false;
  String? _currentErrorText;
  bool _obscureText = false;
  bool _fieldWasSubmitted = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _obscureText = widget.isPassword;
    _currentErrorText = null; // Initialize _currentErrorText

    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleTextChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  void _handleTextChange() {
    if (_fieldWasSubmitted && _currentErrorText != null) {
      final validationError = widget.validator?.call(_controller.text);
      if (validationError == null) {
        if (mounted) {
          setState(() {
            _currentErrorText = null;
          });
        }
      }
    } else if (!_fieldWasSubmitted && _currentErrorText != null) {
      final validationError = widget.validator?.call(_controller.text);
      if (validationError == null) {
        if (mounted) {
          setState(() {
            _currentErrorText = null;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.removeListener(_handleTextChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  Color _getLabelColor(BuildContext context) {
    final theme = Theme.of(context);
    if (_currentErrorText != null) return theme.colorScheme.error;
    if (_isFocused || _controller.text.isNotEmpty) {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.onSurface.withOpacity(0.7);
  }

  IconData? _getErrorIcon() {
    return _currentErrorText != null ? Icons.error_outline : null;
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  String? _validate(String? value) {
    final error = widget.validator?.call(value);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentErrorText != error) {
        setState(() {
          _currentErrorText = error;
          if (error != null) _fieldWasSubmitted = true;
        });
      } else if (mounted && error == null && _currentErrorText != null) {
        setState(() {
          _currentErrorText = null;
        });
      }
    });
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputDecorationTheme = theme.inputDecorationTheme;

    final Color effectiveFillColor =
        inputDecorationTheme.fillColor ??
            (theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3));

    // Определяем цвет текста в нефокусном состоянии
    final Color effectiveTextColor = theme.colorScheme.onSurface.withOpacity(0.85);

    return TextFormField(
      key: widget.formFieldKey,
      controller: _controller,
      focusNode: _focusNode,
      obscureText: _obscureText,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      autovalidateMode: widget.autovalidateMode,
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 14,
        height: 17 / 14,
        color: _isFocused
            ? theme.colorScheme.onSurface
            : effectiveTextColor, // <-- Используем наш effectiveTextColor
      ),
      decoration: InputDecoration(
        labelText: _currentErrorText ?? widget.label,
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: _getLabelColor(context),
        ),
        filled: true,
        fillColor: effectiveFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: (_currentErrorText != null && _isFocused)
              ? BorderSide(color: theme.colorScheme.error, width: 1.5)
              : (_currentErrorText != null && !_isFocused)
              ? BorderSide(color: theme.colorScheme.error, width: 1)
              : (_isFocused
              ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
              : BorderSide.none),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: _currentErrorText != null
              ? BorderSide(color: theme.colorScheme.error, width: 1)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: _currentErrorText != null ? theme.colorScheme.error : theme.colorScheme.primary,
              width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        errorStyle: const TextStyle(height: 0.01, fontSize: 0.01, color: Colors.transparent),
        suffixIcon: widget.isPassword
            ? IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _getLabelColor(context),
            size: 20,
          ),
          onPressed: _togglePasswordVisibility,
        )
            : (_getErrorIcon() != null
            ? Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(
            _getErrorIcon(),
            color: theme.colorScheme.error,
            size: 20,
          ),
        )
            : null),
      ),
      validator: _validate,
    );
  }
}