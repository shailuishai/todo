// lib/widgets/auth/RegisterFrom.dart (или RegisterForm.dart)
import 'package:flutter/material.dart';
// import '../../core/constants/app_assets.dart'; // Не используется в этом файле
import '../CustomInputField.dart';
import '../../core/constants/app_strings.dart';

class RegisterForm extends StatelessWidget { // ИЛИ RegisterFrom, если класс так называется
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final VoidCallback onSubmit;
  final AutovalidateMode autovalidateMode;

  const RegisterForm({ // ИЛИ RegisterFrom
    super.key,
    required this.formKey,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onSubmit,
    required this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    final emailFocusNode = FocusNode();
    final passwordFocusNode = FocusNode();
    final confirmPasswordFocusNode = FocusNode();

    return Form(
      key: formKey,
      // autovalidateMode: autovalidateMode, // Можно установить и на Form
      child: Column(
        children: [
          CustomInputField(
            label: AppStrings.usernameLabel,
            controller: usernameController,
            textInputAction: TextInputAction.next,
            autovalidateMode: autovalidateMode,
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(emailFocusNode);
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppStrings.usernameRequiredError;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.emailLabel,
            controller: emailController,
            focusNode: emailFocusNode,
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
            textInputAction: TextInputAction.next,
            autovalidateMode: autovalidateMode,
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(confirmPasswordFocusNode);
            },
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
          const SizedBox(height: 16),
          CustomInputField(
            label: AppStrings.confirmPasswordLabel,
            controller: confirmPasswordController,
            focusNode: confirmPasswordFocusNode,
            isPassword: true,
            textInputAction: TextInputAction.done,
            autovalidateMode: autovalidateMode,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}