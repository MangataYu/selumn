import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

import '../application/account_controller.dart';
import '../data/account_repository.dart';
import 'account_error_text.dart';

enum _AccountForm { login, register, verify, forgot, reset }

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  var _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _token = TextEditingController();
  _AccountForm _form = .login;
  bool _busy = false;
  Object? _error;
  String? _notice;

  AccountController get _controller =>
      ref.read(accountControllerProvider.notifier);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _token.dispose();
    super.dispose();
  }

  void _selectForm(_AccountForm form) {
    setState(() {
      _form = form;
      _formKey = GlobalKey<FormState>();
      _error = null;
      _notice = null;
      _password.clear();
      _confirmPassword.clear();
      _token.clear();
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? notice,
    _AccountForm? nextForm,
    bool clearSecrets = false,
  }) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _notice = notice;
        if (nextForm != null) {
          _form = nextForm;
          _formKey = GlobalKey<FormState>();
        }
        if (clearSecrets) {
          _password.clear();
          _confirmPassword.clear();
          _token.clear();
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    final email = _email.text.trim();
    final password = _password.text;
    final token = _token.text.trim();
    switch (_form) {
      case .login:
        await _run(
          () => _controller.login(email: email, password: password),
          clearSecrets: true,
        );
      case .register:
        await _run(
          () => _controller.register(email: email, password: password),
          notice: l10n.account.mailAccepted,
          nextForm: .verify,
          clearSecrets: true,
        );
      case .verify:
        await _run(
          () => _controller.verifyEmail(token: token, password: password),
          notice: l10n.account.verified,
          nextForm: .login,
          clearSecrets: true,
        );
      case .forgot:
        await _run(
          () => _controller.forgotPassword(email: email),
          notice: l10n.account.mailAccepted,
          nextForm: .reset,
          clearSecrets: true,
        );
      case .reset:
        await _run(
          () => _controller.resetPassword(token: token, password: password),
          notice: l10n.account.passwordReset,
          nextForm: .login,
          clearSecrets: true,
        );
    }
  }

  Future<void> _resend() async {
    if (_emailError(_email.text) != null) {
      _formKey.currentState?.validate();
      return;
    }
    await _run(
      () => _controller.resendVerification(email: _email.text.trim()),
      notice: context.l10n.account.mailAccepted,
    );
  }

  Future<void> _logout() async {
    final l10n = context.l10n;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.account.logoutTitle,
      message: l10n.account.logoutDescription,
      confirmLabel: l10n.account.logout,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () async {
        try {
          await _controller.logout();
        } catch (error) {
          // The repository clears this device's credentials even if offline.
          if (getIt<AccountRepository>().session == null &&
              error is AccountException &&
              error.code != 'storage_error') {
            throw const AccountException('logout_remote_failed');
          }
          rethrow;
        }
      },
      notice: l10n.account.loggedOut,
      nextForm: .login,
      clearSecrets: true,
    );
  }

  String? _emailError(String? value) {
    final email = value?.trim() ?? '';
    if (email.length > 254 ||
        email.codeUnits.any((unit) => unit > 127) ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return context.l10n.account.emailRequired;
    }
    return null;
  }

  String? _passwordError(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return context.l10n.account.passwordRequired;
    if (_form == .register || _form == .reset) {
      final length = password.runes.length;
      if (length < 12 || length > 128 || utf8.encode(password).length > 512) {
        return context.l10n.account.passwordInvalid;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = getIt<AccountRepository>().config;
    // An unconfigured build never loads credentials or contacts account services.
    final account = config.isEnabled
        ? ref.watch(accountControllerProvider)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.account.title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (config.isEnabled && config.environment != 'production') ...[
                  _InfoCard(
                    title: config.environment == 'staging'
                        ? l10n.account.stagingEnvironment
                        : l10n.account.developmentEnvironment,
                    icon: LucideIcons.flaskConical,
                    highlighted: true,
                  ),
                  const SizedBox(height: 16),
                ],
                _InfoCard(
                  title: l10n.account.localTitle,
                  description: l10n.account.localDescription,
                  icon: LucideIcons.notebookPen,
                ),
                const SizedBox(height: 16),
                if (!config.isEnabled)
                  _InfoCard(
                    title: l10n.account.unavailableTitle,
                    description: l10n.account.unavailableDescription,
                    icon: LucideIcons.userRound,
                  )
                else ...[
                  _InfoCard(
                    title: l10n.account.cloudTitle,
                    description: l10n.account.cloudDescription,
                    icon: LucideIcons.cloud,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        accountErrorText(_error!, l10n),
                        style: context.theme.typography.bodyMedium.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_notice != null) ...[
                    Semantics(liveRegion: true, child: Text(_notice!)),
                    const SizedBox(height: 16),
                  ],
                  account!.when(
                    data: (session) => session == null
                        ? _buildForm()
                        : _buildSignedIn(session.user),
                    error: (error, _) => Column(
                      children: [
                        Text(accountErrorText(error, l10n)),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => ref.invalidate(accountControllerProvider),
                          child: Text(l10n.account.retry),
                        ),
                        TextButton(
                          key: const ValueKey('account-logout'),
                          onPressed: _busy ? null : _logout,
                          child: Text(l10n.account.logout),
                        ),
                      ],
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignedIn(AccountUser user) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.account.signedIn,
          style: context.theme.typography.titleLarge.onSurface,
        ),
        const SizedBox(height: 8),
        SelectableText(user.email),
        const SizedBox(height: 8),
        Text(
          user.emailVerified
              ? l10n.account.emailVerified
              : l10n.account.emailUnverified,
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(_controller.refreshAccount),
          child: Text(l10n.account.refreshAccount),
        ),
        TextButton(
          key: const ValueKey('account-logout'),
          onPressed: _busy ? null : _logout,
          child: Text(l10n.account.logout),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }

  Widget _buildForm() {
    final l10n = context.l10n;
    final newPassword = _form == .register || _form == .reset;
    final hasEmail = _form != .reset;
    final hasToken = _form == .verify || _form == .reset;
    final title = switch (_form) {
      .login => l10n.account.login,
      .register => l10n.account.register,
      .verify => l10n.account.verify,
      .forgot => l10n.account.forgot,
      .reset => l10n.account.reset,
    };
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.theme.typography.titleLarge.onSurface),
          const SizedBox(height: 16),
          if (_form == .verify || _form == .reset) ...[
            Text(
              _form == .verify
                  ? l10n.account.verifyHint
                  : l10n.account.resetHint,
            ),
            const SizedBox(height: 16),
          ],
          if (hasEmail) ...[
            TextFormField(
              key: const ValueKey('account-email'),
              controller: _email,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l10n.account.email),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              validator: _emailError,
            ),
            const SizedBox(height: 16),
          ],
          if (hasToken) ...[
            TextFormField(
              key: const ValueKey('account-token'),
              controller: _token,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _form == .verify
                    ? l10n.account.verificationToken
                    : l10n.account.resetToken,
              ),
              autocorrect: false,
              enableSuggestions: false,
              obscureText: true,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.account.tokenRequired
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (_form != .forgot) ...[
            TextFormField(
              key: const ValueKey('account-password'),
              controller: _password,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _form == .verify
                    ? l10n.account.originalPassword
                    : _form == .reset
                    ? l10n.account.newPassword
                    : l10n.account.password,
                helperText: newPassword ? l10n.account.passwordHint : null,
                helperMaxLines: 2,
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              validator: _passwordError,
              onFieldSubmitted: (_) {
                if (!newPassword) _submit();
              },
            ),
            const SizedBox(height: 16),
          ],
          if (newPassword) ...[
            TextFormField(
              key: const ValueKey('account-confirm-password'),
              controller: _confirmPassword,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.account.confirmPassword,
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              validator: (value) => value == _password.text
                  ? null
                  : l10n.account.passwordMismatch,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            key: const ValueKey('account-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(_form == .forgot ? l10n.account.sendRecovery : title),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (_form == .login) ...[
                _formButton(l10n.account.register, .register),
                _formButton(l10n.account.verify, .verify),
                _formButton(l10n.account.forgot, .forgot),
              ] else
                _formButton(l10n.account.backToLogin, .login),
              if (_form == .verify)
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: Text(l10n.account.resendVerification),
                ),
              if (_form == .forgot)
                _formButton(l10n.account.haveResetToken, .reset),
              if (_form == .reset) _formButton(l10n.account.forgot, .forgot),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formButton(String label, _AccountForm form) => TextButton(
    onPressed: _busy ? null : () => _selectForm(form),
    child: Text(label),
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final bool highlighted;

  const _InfoCard({
    required this.title,
    required this.icon,
    this.description,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? colors.tertiaryContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(context.theme.radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: highlighted
                      ? context.theme.typography.titleMedium.onTertiaryContainer
                      : context.theme.typography.titleMedium.onSurface,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: context.theme.typography.bodyMedium.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}
