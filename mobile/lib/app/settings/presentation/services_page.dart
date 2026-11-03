import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:moodiary_assistant/moodiary_assistant.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_ml/moodiary_ml.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.app.services)),
      body: Padding(
        padding: .symmetric(horizontal: context.spacing.sm),
        child: CustomScrollView(
          slivers: [
            const _AiSection(),
            const _ModelDownloadSection(),
            const _SemanticSection(),
            const _QweatherSection(),
            const _MapSection(),
            SliverGap(context.safeBottom),
          ],
        ),
      ),
    );
  }
}

/// Opens the existing semantic-model controls directly from storage settings.
class ModelManagementPage extends StatelessWidget {
  const ModelManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.storage.manageModels)),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.sm),
        child: _ModelPickerSheet(
          manager: getIt<EmbeddingModelManager>(),
          showAsPage: true,
        ),
      ),
    );
  }
}

class _AiSection extends StatelessWidget {
  const _AiSection();

  @override
  Widget build(BuildContext context) {
    return MSliverSettingGroup(
      title: context.l10n.app.servicesAssistant,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: MoodiaryKVs.assistantActiveProviderId.getNotifier(),
          builder: (context, _, _) => const AssistantSummaryTile(),
        ),
      ],
    );
  }
}

class _ModelDownloadSection extends StatelessWidget {
  const _ModelDownloadSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: MoodiaryKVs.modelDownloadEndpoint.getNotifier(),
      builder: (context, _, _) {
        final endpoint = HfHub.endpoint;
        return MSliverSettingGroup(
          title: context.l10n.app.servicesModelDownload,
          children: [
            SettingListTile(
              leading: Icon(
                LucideIcons.download,
                color: context.theme.colors.onSurfaceVariant,
              ),
              title: context.l10n.app.servicesHfEndpoint,
              subtitle: endpoint,
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: () => _pickEndpoint(context, endpoint),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickEndpoint(BuildContext context, String endpoint) async {
    final selection = endpoint == HfHub.mirrorEndpoint
        ? 'mirror'
        : endpoint == HfHub.officialEndpoint
        ? 'official'
        : 'custom';
    final choice = await MSheet.picker<String>(
      context,
      title: context.l10n.app.servicesHfEndpoint,
      selected: selection,
      options: [
        MSheetOption(
          value: 'mirror',
          label: context.l10n.app.servicesHfMirror,
          subtitle: HfHub.mirrorEndpoint,
          icon: LucideIcons.globe,
        ),
        MSheetOption(
          value: 'official',
          label: context.l10n.app.servicesHfOfficial,
          subtitle: HfHub.officialEndpoint,
          icon: LucideIcons.globe,
        ),
        MSheetOption(
          value: 'custom',
          label: context.l10n.app.servicesHfCustom,
          subtitle: selection == 'custom'
              ? endpoint
              : context.l10n.app.servicesHfCustomHint,
          icon: LucideIcons.server,
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    final String endpointToSave;
    if (choice == 'custom') {
      final result = await MAlert.prompt(
        context,
        title: context.l10n.app.servicesHfCustom,
        message: context.l10n.app.servicesHfHelp,
        initialValue: selection == 'custom' ? endpoint : '',
        hintText: HfHub.officialEndpoint,
        keyboardType: TextInputType.url,
        validator: (value) {
          try {
            HfHub.normalize(value);
            return null;
          } on FormatException {
            return l10n.app.servicesHfInvalid;
          }
        },
      );
      if (result == null) return;
      endpointToSave = HfHub.normalize(result);
    } else {
      endpointToSave = choice == 'mirror'
          ? HfHub.mirrorEndpoint
          : HfHub.officialEndpoint;
    }
    MoodiaryKVs.modelDownloadEndpoint.set(endpointToSave);
    toast.success(message: l10n.app.servicesSaved);
  }
}

class _SemanticSection extends StatefulWidget {
  const _SemanticSection();

  @override
  State<_SemanticSection> createState() => _SemanticSectionState();
}

class _SemanticSectionState extends State<_SemanticSection> {
  late final _manager = getIt<EmbeddingModelManager>();

  bool _rebuilding = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colors;
    return ValueListenableBuilder<String>(
      valueListenable: MoodiaryKVs.embeddingModelId.getNotifier(),
      builder: (context, _, _) {
        final active = _manager.active;
        return MSliverSettingGroup(
          title: context.l10n.app.semanticTitle,
          children: [
            SettingListTile(
              leading: Icon(
                LucideIcons.sparkles,
                color: scheme.onSurfaceVariant,
              ),
              title: context.l10n.app.semanticModelTitle,
              subtitle:
                  active?.displayName ?? context.l10n.app.semanticStateOff,
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: _openPicker,
            ),
            if (active != null)
              SettingListTile(
                leading: Icon(
                  LucideIcons.refreshCw,
                  color: scheme.onSurfaceVariant,
                ),
                title: context.l10n.app.semanticRebuildTitle,
                subtitle: context.l10n.app.semanticRebuildSubtitle,
                trailing: _rebuilding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.chevronRight),
                onTap: _rebuilding ? null : _rebuild,
              ),
          ],
        );
      },
    );
  }

  Future<void> _openPicker() async {
    await MSheet.show<void>(
      context,
      builder: (_) => _ModelPickerSheet(manager: _manager),
    );
    if (mounted) setState(() {});
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    try {
      final count = await getIt<EmbedIndexService>().rebuildAll();
      toast.success(message: l10n.app.semanticRebuildDone(count: count));
    } catch (e, s) {
      logger.e('semantic rebuild failed', error: e, stackTrace: s);
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }
}

class _ModelPickerSheet extends StatefulWidget {
  final EmbeddingModelManager manager;
  final bool showAsPage;

  const _ModelPickerSheet({required this.manager, this.showAsPage = false});

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  EmbeddingModelManager get _manager => widget.manager;
  EmbeddingModelOperation? get _operation => _manager.operation.value;
  bool get _busy => _operation != null;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<EmbeddingModelOperation?>(
        valueListenable: _manager.operation,
        builder: (context, _, _) => _buildContent(context),
      );

  Widget _buildContent(BuildContext context) {
    final scheme = context.theme.colors;
    final active = _manager.active;
    return SafeArea(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: .symmetric(
              horizontal: context.spacing.md,
              vertical: context.spacing.sm,
            ),
            child: Text(
              context.l10n.app.semanticPickTitle,
              style: context.theme.typography.titleMedium.onSurface,
            ),
          ),
          for (final (i, spec) in embeddingModelCatalog.indexed)
            if (widget.showAsPage)
              _pageModelTile(context, spec, isActive: spec.id == active?.id)
            else
              _modelTile(
                context,
                spec,
                isFirst: i == 0,
                isLast: i == embeddingModelCatalog.length - 1 && active == null,
                isActive: spec.id == active?.id,
              ),
          if (active != null)
            SettingListTile(
              isLast: true,
              leading: Icon(LucideIcons.circleOff, color: scheme.error),
              title: context.l10n.app.semanticDisableTitle,
              onTap: _busy ? null : _disable,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _pageModelTile(
    BuildContext context,
    EmbeddingModelSpec spec, {
    required bool isActive,
  }) {
    final downloaded = _manager.isDownloaded(spec);
    final downloading =
        _operation?.kind == EmbeddingModelOperationKind.activate &&
        _operation?.modelId == spec.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modelTile(
          context,
          spec,
          isFirst: true,
          isLast: true,
          isActive: isActive,
        ),
        if (!isActive)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.sm),
            child: Wrap(
              spacing: context.spacing.sm,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _activate(spec),
                  child: Text(
                    downloaded
                        ? context.l10n.app.semanticEnableTitle
                        : context.l10n.app.semanticEnableConfirm,
                  ),
                ),
                if (downloaded)
                  TextButton(
                    onPressed: _busy ? null : () => _delete(spec),
                    child: Text(context.l10n.app.semanticDeleteConfirm),
                  ),
              ],
            ),
          ),
        if (downloading) const SizedBox(height: 8),
      ],
    );
  }

  Widget _modelTile(
    BuildContext context,
    EmbeddingModelSpec spec, {
    required bool isFirst,
    required bool isLast,
    required bool isActive,
  }) {
    final scheme = context.theme.colors;
    final operation = _operation;
    final downloading =
        operation?.kind == EmbeddingModelOperationKind.activate &&
        operation?.modelId == spec.id;
    final downloaded = _manager.isDownloaded(spec);
    final sizeMb = (spec.sizeBytes / (1024 * 1024)).round();
    final status = isActive
        ? context.l10n.app.semanticModelActive
        : downloaded
        ? context.l10n.app.semanticModelDownloaded
        : context.l10n.app.semanticModelNotDownloaded;
    final subtitle = downloading
        ? (operation!.progress < 0
              ? context.l10n.app.semanticVerifying
              : context.l10n.app.semanticDownloading(
                  percent: (operation.progress * 100).toStringAsFixed(0),
                ))
        : widget.showAsPage
        ? '$sizeMb MB · ${_descOf(context, spec)} · $status'
        : '$sizeMb MB · ${_descOf(context, spec)}';
    return SettingListTile(
      isFirst: isFirst,
      isLast: isLast,
      leading: Icon(
        isActive ? LucideIcons.circleCheck : LucideIcons.box,
        color: isActive ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: spec.displayName,
      subtitle: subtitle,
      trailing: downloading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (downloaded && !isActive && !widget.showAsPage)
          ? IconButton(
              icon: Icon(LucideIcons.trash2, color: scheme.onSurfaceVariant),
              onPressed: _busy ? null : () => _delete(spec),
            )
          : null,
      onTap: (widget.showAsPage || isActive || _busy)
          ? null
          : () => _activate(spec),
    );
  }

  String _descOf(BuildContext context, EmbeddingModelSpec spec) {
    return switch (spec.id) {
      'qwen3-embedding-0.6b-int8' => context.l10n.app.semanticDescQwen3,
      _ => '',
    };
  }

  Future<void> _activate(EmbeddingModelSpec spec) async {
    if (_busy) return;
    final downloaded = _manager.isDownloaded(spec);
    final sizeMb = (spec.sizeBytes / (1024 * 1024)).round();
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.app.semanticEnableTitle,
      message: downloaded
          ? l10n.app.semanticActivateLocalMessage
          : l10n.app.semanticActivateDownloadMessage(size: '$sizeMb MB'),
      confirmLabel: downloaded && widget.showAsPage
          ? l10n.app.semanticEnableTitle
          : l10n.app.semanticEnableConfirm,
    );
    if (!confirmed || !mounted) return;
    try {
      final started = await _manager.runOperation(
        kind: EmbeddingModelOperationKind.activate,
        modelId: spec.id,
        action: (progress) async {
          if (!downloaded) {
            await _manager.download(
              spec,
              onProgress: (received, total) =>
                  progress(total > 0 ? received / total : 0),
            );
          }
          progress(-1);
          await _manager.activate(spec);
          unawaited(getIt<EmbedIndexService>().drain());
        },
      );
      if (!started) return;
      toast.success(message: l10n.app.semanticEnabled);
      if (mounted && !widget.showAsPage) Navigator.of(context).pop();
    } catch (e, s) {
      logger.e('activate embedding model failed', error: e, stackTrace: s);
      toast.error(message: l10n.app.semanticEnableFailed);
    }
  }

  Future<void> _delete(EmbeddingModelSpec spec) async {
    if (_busy) return;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.app.semanticDeleteTitle,
      message: l10n.app.semanticDeleteMessage,
      confirmLabel: l10n.app.semanticDeleteConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _manager.runOperation(
        kind: EmbeddingModelOperationKind.delete,
        modelId: spec.id,
        action: (_) => _manager.delete(spec),
      );
    } catch (e, s) {
      logger.e('delete embedding model failed', error: e, stackTrace: s);
      toast.error();
    }
  }

  Future<void> _disable() async {
    if (_busy) return;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.app.semanticDisableTitle,
      message: l10n.app.semanticDisableMessage,
      confirmLabel: l10n.app.semanticDisableConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final started = await _manager.runOperation(
        kind: EmbeddingModelOperationKind.disable,
        modelId: _manager.active?.id ?? '',
        action: (_) async {
          _manager.deactivate();
          await getIt<EmbedIndexService>().clearAll();
        },
      );
      if (!started) return;
      if (!mounted) return;
      if (!widget.showAsPage) {
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      logger.e('disable semantic search failed', error: e, stackTrace: s);
      toast.error();
    }
  }
}

class _QweatherSection extends ConsumerWidget {
  const _QweatherSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.theme.colors;
    return MSliverSettingGroup(
      title: context.l10n.app.servicesQweather,
      children: [
        _SecretKvTile(
          kv: .qweatherKey,
          title: 'API Key',
          leading: Icon(LucideIcons.key, color: scheme.onSurfaceVariant),
        ),
        _KvTile(
          kv: .qweatherApiHost,
          title: 'API Host',
          subtitleWhenEmpty: context.l10n.app.servicesQweatherHostHint,
          leading: Icon(LucideIcons.server, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MapSection extends StatelessWidget {
  const _MapSection();

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colors;
    return ValueListenableBuilder<String>(
      valueListenable: MoodiaryKVs.mapTileSource.getNotifier(),
      builder: (context, value, _) {
        final source = MapTileSource.of(value);
        return MSliverSettingGroup(
          title: context.l10n.app.servicesMap,
          children: [
            SettingListTile(
              leading: Icon(LucideIcons.layers, color: scheme.onSurfaceVariant),
              title: context.l10n.diary.mapSource,
              subtitle: source?.label ?? context.l10n.common.notConfigured,
              onTap: () => showMapSourcePicker(context),
            ),
            if (source == .tianditu)
              _SecretKvTile(
                kv: .tiandituKey,
                title: context.l10n.diary.mapTiandituKey,
                leading: Icon(LucideIcons.key, color: scheme.onSurfaceVariant),
              ),
          ],
        );
      },
    );
  }
}

class _KvTile extends StatelessWidget {
  final MoodiaryKVs<String> kv;
  final String title;
  final Widget? leading;
  final String? subtitleWhenEmpty;

  const _KvTile({
    required this.kv,
    required this.title,
    this.leading,
    this.subtitleWhenEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: kv.getNotifierOr(''),
      builder: (context, value, _) {
        return SettingInputTile(
          title: title,
          leading: leading,
          value: value,
          subtitle: value.isEmpty
              ? (subtitleWhenEmpty ?? context.l10n.common.notConfigured)
              : context.l10n.common.configured,
          onValue: (v) async {
            kv.set(v);
            toast.success(message: l10n.app.servicesSaved);
          },
        );
      },
    );
  }
}

class _SecretKvTile extends ConsumerWidget {
  final MoodiarySecureKVs kv;
  final String title;
  final Widget? leading;

  const _SecretKvTile({required this.kv, required this.title, this.leading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(secretKvProvider(kv)).value ?? '';
    return SettingInputTile(
      title: title,
      leading: leading,
      value: value,
      subtitle: value.isEmpty
          ? context.l10n.common.notConfigured
          : context.l10n.common.configured,
      onValue: (v) async {
        try {
          await kv.set(v);
        } catch (e, s) {
          logger.e('保存 $kv 失败', error: e, stackTrace: s);
          toast.error(message: l10n.app.servicesSaveFailed);
          return;
        }
        if (!context.mounted) return;
        ref.invalidate(secretKvProvider(kv));
        toast.success(message: l10n.app.servicesSaved);
      },
    );
  }
}
