import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../core/util/countries.dart';
import '../../core/util/phone.dart';
import '../../shared/widgets/widgets.dart';

/// First-run / sign-in screen. Phone + password; unknown numbers auto-create an
/// account (OTP deferred per the backend MVP). Mirrors the mockup `LoginScreen`
/// minus the admin entry (admin is managed in the Appwrite Console).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  Country _country = kDefaultCountry;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final phone = composeInternationalPhone(_country.dialCode, _phone.text);
    ref.read(appControllerProvider.notifier).signIn(phone, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final t = state.t;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: c.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/icon/moona_icon_foreground.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  t.appName,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: c.onSurface,
                  ),
                ),
                Text(
                  t.tagline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  t.loginTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.loginSub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: c.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 26),
                MoonaPhoneField(
                  controller: _phone,
                  country: _country,
                  onCountryChanged: (country) =>
                      setState(() => _country = country),
                  isArabic: t.isArabic,
                  label: t.phone,
                  placeholder: t.phoneHint,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                MoonaField(
                  controller: _password,
                  label: t.password,
                  placeholder: '••••••',
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  error: state.loginError,
                ),
                const SizedBox(height: 20),
                MoonaButton(
                  label: t.signIn,
                  full: true,
                  height: 52,
                  onPressed: state.busy ? null : _submit,
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: 0.9,
                  child: Text(
                    t.newAccountNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                  ),
                ),
                if (state.busy) ...[
                  const SizedBox(height: 18),
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
