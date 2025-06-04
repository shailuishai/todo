// lib/widgets/auth/RegisterForm.dart
import 'package:flutter/material.dart';
import '../CustomInputField.dart';
import '../../core/constants/app_strings.dart';

class RegisterForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final VoidCallback onSubmit;
  final AutovalidateMode autovalidateMode;
  // Раскомментируй, если будешь передавать FocusNodes из AuthScreenState
  // final FocusNode? usernameFocusNode;
  // final FocusNode? emailFocusNode;
  // final FocusNode? passwordFocusNode;
  // final FocusNode? confirmPasswordFocusNode;

  const RegisterForm({
    super.key,
    required this.formKey,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onSubmit,
    required this.autovalidateMode,
    // this.usernameFocusNode,
    // this.emailFocusNode,
    // this.passwordFocusNode,
    // this.confirmPasswordFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    // Пример с локальными FocusNode, если не передаются извне
    final FocusNode localEmailFocusNode = FocusNode();
    final FocusNode localPasswordFocusNode = FocusNode();
    final FocusNode localConfirmPasswordFocusNode = FocusNode();

    return Form(
      key: formKey,
      autovalidateMode: autovalidateMode,
      child: Column(
        children: [
          CustomInputField(
            label: AppStrings.usernameLabel,
            controller: usernameController,
            // focusNode: usernameFocusNode,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) {
              // FocusScope.of(context).requestFocus(emailFocusNode ?? localEmailFocusNode);
              FocusScope.of(context).requestFocus(localEmailFocusNode);
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppStrings.usernameRequiredError;
              }
              if (value.trim().length < 3) {
                return 'Логин должен быть не менее 3 символов';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.emailLabel,
            controller: emailController,
            // focusNode: emailFocusNode ?? localEmailFocusNode,
            focusNode: localEmailFocusNode,
            keyboardType: TextInputType.emailAddress, // Используем keyboardType из CustomInputField
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) {
              // FocusScope.of(context).requestFocus(passwordFocusNode ?? localPasswordFocusNode);
              FocusScope.of(context).requestFocus(localPasswordFocusNode);
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppStrings.emailRequiredError;
              }
              final emailRegExp = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
              if (!emailRegExp.hasMatch(value.trim())) {
                return AppStrings.invalidEmailError;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.passwordLabel,
            controller: passwordController,
            // focusNode: passwordFocusNode ?? localPasswordFocusNode,
            focusNode: localPasswordFocusNode,
            isPassword: true,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) {
              // FocusScope.of(context).requestFocus(confirmPasswordFocusNode ?? localConfirmPasswordFocusNode);
              FocusScope.of(context).requestFocus(localConfirmPasswordFocusNode);
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.passwordRequiredError;
              }
              if (value.length < 6) {
                return AppStrings.passwordMinLengthError;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.confirmPasswordLabel,
            controller: confirmPasswordController,
            // focusNode: confirmPasswordFocusNode ?? localConfirmPasswordFocusNode,
            focusNode: localConfirmPasswordFocusNode,
            isPassword: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.confirmPasswordRequiredError;
              }
              if (value != passwordController.text) {
                return AppStrings.passwordsDoNotMatchError;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}