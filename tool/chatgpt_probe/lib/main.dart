import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mui/mui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'i18n/strings.g.dart';
import 'src/probe_controller.dart';
import 'src/protocol.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const ProbeApp()));
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key, this.controller});

  final ProbeController? controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: probeL10n.title,
    debugShowCheckedModeBanner: false,
    theme: buildMuiTheme(brightness: Brightness.light),
    darkTheme: buildMuiTheme(brightness: Brightness.dark),
    localizationsDelegates: const [GlobalMuiLocalizations.delegate],
    home: ProbePage(controller: controller),
  );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key, this.controller});

  final ProbeController? controller;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  late final ProbeController _controller;
  bool _testRequested = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        ProbeController(callbackMessage: probeL10n.callbackMessage);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    await _controller.signIn();
    await _loadModelsAfterLogin();
  }

  Future<void> _loadModelsAfterLogin() async {
    if (mounted &&
        _controller.planEnabled &&
        !_controller.busy &&
        _controller.models.isEmpty) {
      await _controller.loadModels();
    }
  }

  Future<void> _pasteCallback() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CallbackDialog(controller: _controller),
    );
    await _loadModelsAfterLogin();
  }

  bool get _testSucceeded =>
      _controller.phase == 'completed' &&
      _controller.errorCode == null &&
      _controller.steps.any((step) => step.code == 'response' && step.passed);

  Future<void> _runTest({bool refresh = false}) async {
    if (_controller.busy) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _testRequested = true);
    if (refresh) {
      await _controller.refreshAndTest();
    } else {
      await _controller.sendTest();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _testSucceeded ? probeL10n.testSuccess : probeL10n.testFailed,
        ),
      ),
    );
  }

  Future<void> _openUsage() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://chatgpt.com/settings/usage'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('browser_unavailable');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(probeL10n.genericError)));
    }
  }

  String _errorMessage(String code) {
    if (code == 'pending_authorization_invalid' ||
        code == 'no_pending_authorization') {
      return probeL10n.callbackExpiredError;
    }
    if (code == 'authorization_timeout') {
      return probeL10n.authorizationTimeoutError;
    }
    if (code == 'browser_launch_timeout') {
      return probeL10n.browserLaunchTimeoutError;
    }
    if (code == 'remote_revocation_unconfirmed') {
      return probeL10n.revocationError;
    }
    if (code == 'unexpected_html_response') return probeL10n.htmlResponseError;
    if (code == 'unexpected_json_response') return probeL10n.jsonResponseError;
    if (code == 'empty_response_body') return probeL10n.emptyResponseError;
    if (code.contains('timeout')) return probeL10n.timeoutError;
    if (code == 'unexpected_response_content_type' ||
        code == 'invalid_response') {
      return probeL10n.responseFormatError;
    }
    if (code.startsWith('response_') || code == 'invalid_response_event') {
      return probeL10n.incompleteResponseError;
    }
    if (code.contains('usage_limit')) return probeL10n.limitError;
    if (code.contains('permission') ||
        code.contains('eligible') ||
        code.contains('scope')) {
      return probeL10n.permissionError;
    }
    if (code.contains('network')) return probeL10n.networkError;
    if (code.contains('token') ||
        code.contains('nonce') ||
        code.contains('signature') ||
        code.contains('state') ||
        code.contains('grant')) {
      return probeL10n.loginError;
    }
    return probeL10n.genericError;
  }

  String get _diagnostics => [
    'Selume ChatGPT Probe 0.1.4',
    'phase=${_controller.phase}',
    if (_controller.failedPhase != null)
      'failed_phase=${_controller.failedPhase}',
    if (_controller.failedElapsedSeconds != null)
      'elapsed_seconds=${_controller.failedElapsedSeconds}',
    if (_controller.errorCode != null) 'code=${_controller.errorCode}',
    if (_controller.errorHttpStatus != null)
      'http=${_controller.errorHttpStatus}',
    if (_controller.errorRequestId != null)
      'request_id=${_controller.errorRequestId}',
    if (_controller.responseFormat != null)
      'response_format=${_controller.responseFormat}',
    if (_controller.responseBodyFormat != null)
      'body_format=${_controller.responseBodyFormat}',
    if (_controller.responseBytes != null)
      'received_bytes=${_controller.responseBytes}',
    for (final step in _controller.steps) '${step.code}=${step.passed}',
  ].join('\n');

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: _diagnostics));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(probeL10n.copied)));
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final c = _controller;
      final text = probeL10n;
      final theme = Theme.of(context);
      final showTestFeedback =
          _testRequested &&
          (c.phase == 'testing' ||
              c.phase == 'refreshing' ||
              c.phase == 'completed' ||
              (c.phase == 'failed' &&
                  (c.failedPhase == 'testing' ||
                      c.failedPhase == 'refreshing')));
      return Scaffold(
        appBar: AppBar(title: Text(text.title)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(text.badge, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 12),
                  Text(text.heading, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(text.intro, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  _section(text.accountTitle, [
                    if (c.signedIn) ...[
                      Text('${text.account}: ${c.email ?? "—"}'),
                      Text(
                        c.planEnabled ? text.permissionOn : text.permissionOff,
                      ),
                    ],
                    if (!c.signedIn || !c.planEnabled)
                      FilledButton(
                        onPressed: c.busy ? null : _login,
                        child: Text(c.signedIn ? text.reauthorize : text.login),
                      ),
                    if (!c.signedIn) Text(text.loginHint),
                    if (c.hasPendingSignIn) ...[
                      Text(text.pasteCallbackHint),
                      OutlinedButton.icon(
                        onPressed: c.canPasteCallback ? _pasteCallback : null,
                        icon: const Icon(
                          Icons.content_paste_outlined,
                          size: 18,
                        ),
                        label: Text(text.pasteCallback),
                      ),
                    ],
                    if (c.phase == 'waiting_browser' ||
                        (c.hasPendingSignIn && !c.busy))
                      OutlinedButton(
                        onPressed: c.cancelSignIn,
                        child: Text(text.cancel),
                      ),
                    if (c.signedIn)
                      TextButton(
                        onPressed: c.busy ? null : c.signOut,
                        child: Text(text.signOut),
                      ),
                  ]),
                  _section(text.resultTitle, [
                    if (c.busy) const LinearProgressIndicator(),
                    Text(text.phases[c.phase] ?? c.phase),
                    for (final step in c.steps)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            step.passed
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: step.passed
                                ? context.theme.success
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(text.steps[step.code] ?? step.code),
                          ),
                        ],
                      ),
                    if (c.errorCode case final String code) ...[
                      Text(
                        text.errorTitle,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      Text(_errorMessage(code)),
                      if (c.failedPhase case final String failedPhase)
                        Text(
                          '${text.failedAt}: ${text.phases[failedPhase] ?? failedPhase}',
                        ),
                      SelectableText('${text.diagnostic}: $code'),
                      if (c.errorHttpStatus != null)
                        Text('HTTP ${c.errorHttpStatus}'),
                    ],
                    TextButton.icon(
                      onPressed: _copyDiagnostics,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(text.copy),
                    ),
                  ]),
                  _section(text.modelTitle, [
                    Text(text.modelHint),
                    OutlinedButton(
                      onPressed: c.busy || !c.planEnabled ? null : c.loadModels,
                      child: Text(text.loadModels),
                    ),
                    if (c.models.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(c.selectedModel),
                        initialValue: c.selectedModel,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: text.modelLabel),
                        hint: Text(text.chooseModel),
                        items: [
                          for (final model in c.models)
                            DropdownMenuItem(
                              value: model.id,
                              child: Text(
                                model.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: c.busy
                            ? null
                            : (value) => c.selectedModel = value,
                      ),
                    Text(text.testPrompt),
                    FilledButton(
                      onPressed:
                          c.busy || !c.planEnabled || c.selectedModel == null
                          ? null
                          : () => _runTest(),
                      child: Text(text.test),
                    ),
                    if (showTestFeedback) ...[
                      if (c.busy) const LinearProgressIndicator(),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          c.busy
                              ? text.testRunning
                              : _testSucceeded
                              ? text.testSuccess
                              : text.testFailed,
                          key: const ValueKey('test-status'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: c.busy
                                ? theme.colorScheme.primary
                                : _testSucceeded
                                ? context.theme.success
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                      if (c.errorCode case final String code) ...[
                        Text(_errorMessage(code)),
                        SelectableText('${text.diagnostic}: $code'),
                        TextButton.icon(
                          onPressed: _copyDiagnostics,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(text.copy),
                        ),
                      ],
                      if (c.reply.isNotEmpty) ...[
                        Text(
                          _testSucceeded ? text.replyTitle : text.partialReply,
                          style: theme.textTheme.labelMedium,
                        ),
                        SelectableText(c.reply),
                      ],
                      if (_testSucceeded)
                        Text(
                          text.restartHint,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                    OutlinedButton(
                      onPressed:
                          c.busy || !c.planEnabled || c.selectedModel == null
                          ? null
                          : () => _runTest(refresh: true),
                      child: Text(text.refreshTest),
                    ),
                    Text(text.refreshHint, style: theme.textTheme.bodySmall),
                  ]),
                  OutlinedButton.icon(
                    onPressed: _openUsage,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(text.usage),
                  ),
                  const SizedBox(height: 12),
                  Text(text.usageHint, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CallbackDialog extends StatefulWidget {
  const _CallbackDialog({required this.controller});

  final ProbeController controller;

  @override
  State<_CallbackDialog> createState() => _CallbackDialogState();
}

class _CallbackDialogState extends State<_CallbackDialog> {
  final _input = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final address = _input.text;
    _input.clear();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.controller.submitCallbackUrl(address);
      if (mounted) Navigator.of(context).pop();
    } on ProbeException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            error.code.contains('expired') ||
                error.code.contains('no_pending') ||
                error.code == 'pending_authorization_invalid' ||
                error.code == 'authorization_timeout'
            ? probeL10n.callbackExpiredError
            : probeL10n.callbackInputError;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = probeL10n.genericError;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      scrollable: true,
      title: Text(probeL10n.pasteCallback),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(probeL10n.pasteCallbackInstructions),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            enabled: !_submitting,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.url,
            maxLength: 20000,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: InputDecoration(labelText: probeL10n.callbackUrlLabel),
            onSubmitted: (_) => _submit(),
          ),
          if (_error case final String message) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_submitting) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            Text(probeL10n.callbackSubmitting),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(probeL10n.callbackClose),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(probeL10n.callbackSubmit),
        ),
      ],
    ),
  );
}
