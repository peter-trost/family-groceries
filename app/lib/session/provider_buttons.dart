import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

const _height = 44.0;
const _radius = BorderRadius.all(Radius.circular(_height / 2));

/// Google's sign-in button: standard "G" from Google's asset kit, light or
/// dark theme colors, pill shape.
/// https://developers.google.com/identity/branding-guidelines
class const GoogleSignInButton({
  required final String label,
  required final VoidCallback? onPressed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, stroke, text) = dark
        ? (
            const Color(0xFF131314),
            const Color(0xFF8E918F),
            const Color(0xFFE3E3E3),
          )
        : (Colors.white, const Color(0xFF747775), const Color(0xFF1F1F1F));
    return SizedBox(
      height: _height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: text,
          side: BorderSide(color: stroke),
          shape: const RoundedRectangleBorder(borderRadius: _radius),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(
            fontFamily: 'Google Sans',
            fontFamilyFallback: ['Roboto'],
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/google_g.png', width: 20, height: 20),
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Apple's sign-in button as the sign_in_with_apple package draws it to the
/// Human Interface Guidelines: black on light, white on dark.
class const AppleSignInButton({
  required final String label,
  required final VoidCallback? onPressed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: SignInWithAppleButton(
      text: label,
      borderRadius: _radius,
      style: Theme.of(context).brightness == Brightness.dark
          ? SignInWithAppleButtonStyle.white
          : SignInWithAppleButtonStyle.black,
      onPressed: onPressed,
    ),
  );
}
