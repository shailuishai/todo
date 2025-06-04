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
  // final FocusNode? emailFocusNode; // Раскомментируй, если будешь передавать
  // final FocusNode? passwordFocusNode; // Раскомментируй, если будешь передавать

  const LoginForm({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.onSubmit,
    required this.autovalidateMode,
    // this.emailFocusNode, // Раскомментируй, если будешь передавать
    // this.passwordFocusNode, // Раскомментируй, если будешь передавать
  });

  @override
  Widget build(BuildContext context) {
    // Если FocusNode не передается, можно создать локальный здесь,
    // но тогда его нужно будет диспозить, что делает StatelessWidget менее подходящим.
    // Лучше передавать из AuthScreenState.
    final FocusNode localPasswordFocusNode = FocusNode(); // Пример локального

    return Form(
      key: formKey,
      autovalidateMode: autovalidateMode,
      child: Column(
        children: [
          CustomInputField(
            label: AppStrings.emailOrLoginLabel,
            controller: emailController,
            // focusNode: emailFocusNode, // Используй переданный, если есть
            keyboardType: TextInputType.emailAddress, // Используем keyboardType из CustomInputField
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) {
              // FocusScope.of(context).requestFocus(passwordFocusNode ?? localPasswordFocusNode);
              FocusScope.of(context).requestFocus(localPasswordFocusNode); // Пример с локальным
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.passwordLabel,
            controller: passwordController,
            // focusNode: passwordFocusNode ?? localPasswordFocusNode, // Используй переданный или локальный
            focusNode: localPasswordFocusNode, // Пример с локальным
            isPassword: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.passwordRequiredError;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}