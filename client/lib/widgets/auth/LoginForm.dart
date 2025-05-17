// lib/widgets/auth/LoginForm.dart
import 'package:flutter/material.dart';
import '../CustomInputField.dart';
import '../../core/constants/app_strings.dart';

class LoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onSubmit;
  final AutovalidateMode autovalidateMode;

  const LoginForm({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.onSubmit,
    required this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    final passwordFocusNode = FocusNode();

    return Form(
      key: formKey,
      // autovalidateMode: autovalidateMode, // Можно установить и на Form, но мы управляем каждым полем
      child: Column(
        children: [
          CustomInputField(
            label: AppStrings.emailOrLoginLabel,
            controller: emailController,
            textInputAction: TextInputAction.next,
            autovalidateMode: autovalidateMode,
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(passwordFocusNode);
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.emailRequiredError;
              }
              if (!value.contains('@') || !value.contains('.')) {
                return AppStrings.invalidEmailError;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.passwordLabel,
            controller: passwordController,
            focusNode: passwordFocusNode,
            isPassword: true,
            autovalidateMode: autovalidateMode,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.passwordRequiredError;
              }
              if (value.length < 6) {
                return AppStrings.passwordMinLengthError;
              }
              if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d).{6,}$').hasMatch(value)) {
                return AppStrings.passwordComplexityError;
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}