import 'dart:io';

import 'package:flutter/services.dart';
import 'package:moodiary_assistant/src/data/chatgpt_provider_auth.dart';
import 'package:moodiary_assistant/src/data/llm_provider_repository.dart';
import 'package:moodiary_assistant/src/data/model_resolver.dart';
import 'package:moodiary_assistant/src/presentation/model_picker_sheet.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';
import 'package:url_launcher/url_launcher.dart';

class AssistantChatGptPage extends StatefulWidget {
  const AssistantChatGptPage({super.key, this.id});

  final String? id;

  factory AssistantChatGptPage.fromRoute(GoRouterState state) =>
      AssistantChatGptPage(id: state.params['id'] as String?);

  @override
  State<AssistantChatGptPage> createState() => _AssistantChatGptPageState();
}

class _AssistantChatGptPageState extends State<AssistantChatGptPage> {
  late final _repo = getIt<LlmProviderRepository>();
  late final _auth = getIt<ChatGptProviderAuth>();
  late final String _id = widget.id ?? uuidV7();
  final _name = TextEditingController();
  ChatGptSession? _session;
  LlmProvider? _provider;
  String? _model;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      setState(() => _loading = false);
      return;
    }
    try {
      if (widget.id != null) _provider = await _repo.getProvider(_id);
      if (!mounted) return;
      if (widget.id != null &&
          _provider?.protocol != AssistantProviderType.chatgptSubscription) {
        Navigator.of(context).pop();
        return;
      }
      _name.text = _provider?.name ?? context.l10n.assistant.chatGptTitle;
      _model = _provider?.defaultModel;
      final session = _auth.session(_id);
      _session = session;
      session.addListener(_changed);
      if (widget.id != null) await session.initialize();
      if (!mounted) return;
      if (session.planEnabled && session.models.isEmpty) await _refreshModels();
    } catch (_) {
      _error = 'storage_error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _name.dispose();
    // The provider owns the session, so leaving this page preserves pending
    // authorization and its original deadline for a later return.
    super.dispose();
  }

  Future<void> _ensureProvider() async {
    if (_provider != null) return;
    final fallbackName = context.l10n.assistant.chatGptTitle;
    final provider = LlmProvider(
      id: _id,
      name: _name.text.trim().isEmpty ? fallbackName : _name.text.trim(),
      type: AssistantProviderType.chatgptSubscription.id,
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: '',
      createdAt: DateTime.timestamp(),
      sortOrder: await _repo.nextSortOrder(),
      toolCall: true,
    );
    await _repo.upsertProvider(provider);
    _provider = provider;
  }

  Future<void> _login() async {
    setState(() => _error = null);
    try {
      // Save the ID before opening the browser, so process restart can reopen
      // the same encrypted pending request from the providers list.
      await _ensureProvider();
      await _session!.signIn();
      if (_session!.planEnabled) await _refreshModels();
    } catch (error) {
      if (mounted) setState(() => _error = _safeCode(error));
    }
  }

  Future<void> _refreshModels() async {
    final session = _session!;
    if (session.busy) return;
    await session.loadModels();
    if (!mounted ||
        (session.errorCode != null && session.errorCode != 'no_models')) {
      return;
    }
    final ids = session.models.map((model) => model.id).toList();
    if (!ids.contains(_model)) _model = null;
    final existing = _provider;
    if (existing != null) {
      final updated = existing.copyWith(
        models: ids,
        defaultModel: ids.contains(existing.defaultModel)
            ? existing.defaultModel
            : '',
      );
      await _repo.upsertProvider(updated);
      _provider = updated;
    }
    if (mounted) setState(() {});
  }

  Future<void> _paste() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CallbackDialog(session: _session!),
    );
    if (mounted && _session!.planEnabled && _session!.models.isEmpty) {
      await _run(_refreshModels);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _safeCode(error));
    }
  }

  Future<void> _pickModel() async {
    final options = [
      for (final model in _session!.models)
        ModelOption(
          id: model.id,
          label: model.label,
          preset: null,
          levels: const [],
        ),
    ];
    final choice = await showModelPicker(
      context,
      providerName: _name.text.trim(),
      options: options,
      modelId: _model ?? '',
    );
    if (choice != null && mounted) setState(() => _model = choice);
  }

  Future<void> _save() async {
    final session = _session!;
    final model = _model;
    if (!session.planEnabled ||
        model == null ||
        !session.models.any((item) => item.id == model)) {
      toast.info(message: context.l10n.assistant.chatGptNeedModel);
      return;
    }
    setState(() => _saving = true);
    final fallbackName = context.l10n.assistant.chatGptTitle;
    try {
      await _ensureProvider();
      final provider = _provider!.copyWith(
        name: _name.text.trim().isEmpty ? fallbackName : _name.text.trim(),
        defaultModel: model,
        models: session.models.map((item) => item.id).toList(),
      );
      await _repo.upsertProvider(provider);
      if ((MoodiaryKVs.assistantActiveProviderId.get() ?? '').isEmpty) {
        MoodiaryKVs.assistantActiveProviderId.set(_id);
      }
      if (!mounted) return;
      toast.success(message: context.l10n.assistant.chatGptSaved);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _safeCode(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.l10n.assistant;
    final session = _session;
    final busy = _saving || (session?.busy ?? false);
    final code = _error ?? session?.errorCode;
    return Scaffold(
      appBar: AppBar(title: Text(text.chatGptTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !Platform.isAndroid
          ? Center(child: Text(text.chatGptUnsupported))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(text.chatGptIntro),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  enabled: !busy,
                  decoration: InputDecoration(labelText: text.chatGptName),
                ),
                const SizedBox(height: 20),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(text.chatGptBusy),
                ],
                if (session != null) ...[
                  Text(
                    session.signedIn
                        ? text.chatGptLoggedIn
                        : text.chatGptNeedLogin,
                  ),
                  if (session.email != null)
                    Text('${text.chatGptAccount}: ${session.email}'),
                  if (session.signedIn && !session.planEnabled)
                    Text(text.chatGptPermissionMissing),
                  if (session.phase == 'waiting_browser')
                    Text(text.chatGptWaiting),
                  if (session.hasPendingSignIn) ...[
                    const SizedBox(height: 12),
                    Text(text.chatGptPending),
                    OutlinedButton.icon(
                      onPressed: session.canPasteCallback ? _paste : null,
                      icon: const Icon(LucideIcons.clipboardPaste),
                      label: Text(text.chatGptPaste),
                    ),
                    TextButton(
                      onPressed: () => _run(session.cancelSignIn),
                      child: Text(text.chatGptCancel),
                    ),
                  ],
                  if (!session.signedIn || !session.planEnabled)
                    FilledButton(
                      onPressed: busy ? null : _login,
                      child: Text(text.chatGptLogin),
                    ),
                  if (session.signedIn)
                    TextButton(
                      onPressed: busy ? null : () => _run(session.signOut),
                      child: Text(text.chatGptLogout),
                    ),
                  const SizedBox(height: 20),
                  Text(text.chatGptModelsHint),
                  OutlinedButton(
                    onPressed: busy || !session.planEnabled
                        ? null
                        : () => _run(_refreshModels),
                    child: Text(text.chatGptLoadModels),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(text.modelProviderModel),
                    subtitle: Text(
                      session.models
                              .where((item) => item.id == _model)
                              .firstOrNull
                              ?.label ??
                          text.chatGptNeedModel,
                    ),
                    trailing: const Icon(LucideIcons.chevronDown),
                    onTap: busy || session.models.isEmpty ? null : _pickModel,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : _save,
                    child: Text(text.chatGptSave),
                  ),
                  TextButton.icon(
                    onPressed: () => _run(() async {
                      if (!await launchUrl(
                        Uri.parse('https://chatgpt.com/settings/usage'),
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw const ChatGptException('browser_unavailable');
                      }
                    }),
                    icon: const Icon(LucideIcons.externalLink),
                    label: Text(text.chatGptUsage),
                  ),
                ],
                if (code != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText(context, code),
                    style: context.theme.typography.bodyMedium.onSurface
                        .copyWith(color: context.theme.colors.error),
                  ),
                  SelectableText(code),
                ],
              ],
            ),
    );
  }
}

String _safeCode(Object error) =>
    error is ChatGptException ? error.code : 'storage_error';

String _errorText(BuildContext context, String code) {
  final text = context.l10n.assistant;
  if (code == 'remote_revocation_unconfirmed') return text.chatGptLogoutFailed;
  if (code.contains('timeout')) return text.chatGptTimeout;
  if (code == 'storage_error') return text.chatGptStorageError;
  if (code == 'permission_missing') return text.chatGptPermissionMissing;
  return text.chatGptAuthError;
}

class _CallbackDialog extends StatefulWidget {
  const _CallbackDialog({required this.session});
  final ChatGptSession session;

  @override
  State<_CallbackDialog> createState() => _CallbackDialogState();
}

class _CallbackDialogState extends State<_CallbackDialog> {
  final _input = TextEditingController();
  bool _submitting = false;
  bool _failed = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final raw = _input.text;
    _input.clear();
    setState(() {
      _submitting = true;
      _failed = false;
    });
    try {
      await widget.session.submitCallbackUrl(raw);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.l10n.assistant;
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        scrollable: true,
        title: Text(text.chatGptPaste),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text.chatGptPasteHint),
            const SizedBox(height: 12),
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
              decoration: InputDecoration(labelText: text.chatGptCallbackLabel),
              onSubmitted: (_) => _submit(),
            ),
            if (_failed) Text(text.chatGptCallbackInvalid),
            if (_submitting) const LinearProgressIndicator(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.common.cancel),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(context.l10n.common.ok),
          ),
        ],
      ),
    );
  }
}
