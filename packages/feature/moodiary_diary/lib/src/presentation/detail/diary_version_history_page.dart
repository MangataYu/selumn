import 'dart:async';

import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

enum _VersionResult { unchanged, reload, restored }

typedef _VersionAction = Future<_VersionResult> Function(BuildContext context);

class DiaryVersionHistoryPage extends StatefulWidget {
  final String diaryId;

  const DiaryVersionHistoryPage({super.key, required this.diaryId});

  static Future<bool?> open(BuildContext context, String diaryId) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DiaryVersionHistoryPage(diaryId: diaryId),
        ),
      );

  @override
  State<DiaryVersionHistoryPage> createState() =>
      _DiaryVersionHistoryPageState();
}

class _DiaryVersionHistoryPageState extends State<DiaryVersionHistoryPage> {
  static const _pageSize = 20;

  final _versions = <DiaryVersion>[];
  late final _repository = getIt<DiaryRepository>();
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  bool _acting = false;

  bool get _busy => _loading || _acting;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _loadMore({bool reload = false}) async {
    if (_busy || (!reload && !_hasMore)) return;
    setState(() {
      if (reload) {
        _versions.clear();
        _hasMore = true;
      }
      _loading = true;
      _loadFailed = false;
    });
    try {
      final page = await _repository.getDiaryVersions(
        widget.diaryId,
        limit: _pageSize + 1,
        beforeId: _versions.lastOrNull?.id,
      );
      if (!mounted) return;
      setState(() {
        _versions.addAll(page.take(_pageSize));
        _hasMore = page.length > _pageSize;
        _loading = false;
      });
    } catch (error, stack) {
      logger.e(
        'diary version history lookup failed',
        error: error.runtimeType,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _perform(_VersionAction action) async {
    if (_busy || _versions.isEmpty) return;
    setState(() => _acting = true);
    final _VersionResult result;
    try {
      result = await action(context);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _handleResult(result);
  }

  Future<void> _handleResult(_VersionResult result) async {
    if (!mounted) return;
    switch (result) {
      case .unchanged:
        return;
      case .reload:
        await _loadMore(reload: true);
      case .restored:
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(true);
        }
    }
  }

  Future<_VersionResult> _delete(
    BuildContext context, {
    DiaryVersion? version,
  }) async {
    final diaryId = widget.diaryId;
    final l10n = context.l10n;
    try {
      final confirmed = await MAlert.confirm(
        context,
        title: version == null
            ? l10n.diary.versionHistoryClear
            : l10n.diary.versionHistoryDelete,
        message: version == null
            ? l10n.diary.versionHistoryClearMessage
            : l10n.diary.versionHistoryDeleteMessage(
                time: TimeFormat.fullDateTime(version.diary.lastModified),
              ),
        confirmLabel: version == null
            ? l10n.diary.versionHistoryClear
            : l10n.common.delete,
        isDestructive: true,
      );
      if (!mounted || !context.mounted || !confirmed) return .unchanged;
      if (version == null) {
        await _repository.clearDiaryVersions(diaryId);
      } else {
        await _repository.deleteDiaryVersion(diaryId, version);
      }
      return .reload;
    } catch (error, stack) {
      logger.e(
        'diary version history deletion failed',
        error: error.runtimeType,
        stackTrace: stack,
      );
      if (context.mounted) {
        toast.error(message: l10n.diary.versionHistoryDeleteFailed);
      }
      return .unchanged;
    }
  }

  Future<_VersionResult> _restore(
    BuildContext context,
    DiaryVersion version,
  ) async {
    final diaryId = widget.diaryId;
    final l10n = context.l10n;
    try {
      final confirmed = await MAlert.confirm(
        context,
        title: l10n.diary.versionHistoryRestore,
        message: l10n.diary.versionHistoryRestoreMessage,
        confirmLabel: l10n.diary.recycleRestore,
      );
      if (!mounted || !context.mounted || !confirmed) return .unchanged;

      final restored = await _repository.restoreDiaryVersion(diaryId, version);
      if (context.mounted) {
        if (restored) {
          toast.success(message: l10n.diary.versionHistoryRestored);
        } else {
          toast.error(message: l10n.diary.versionHistoryRestoreUnavailable);
        }
      }
      return restored ? .restored : .reload;
    } catch (error, stack) {
      logger.e(
        'diary version restoration failed',
        error: error.runtimeType,
        stackTrace: stack,
      );
      if (context.mounted) {
        toast.error(message: l10n.diary.versionHistoryRestoreFailed);
      }
      return .unchanged;
    }
  }

  Future<void> _openVersion(DiaryVersion version) async {
    final result = await Navigator.of(context).push<_VersionResult>(
      MaterialPageRoute(
        builder: (_) => _DiaryVersionPreview(
          version: version.diary,
          onRestore: (context) => _restore(context, version),
          onDelete: (context) => _delete(context, version: version),
        ),
      ),
    );
    if (result != null) await _handleResult(result);
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_acting,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.diary.versionHistory),
        actions: [
          if (_versions.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => _perform(_delete),
              child: Text(context.l10n.diary.versionHistoryClear),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const .symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.l10n.diary.versionHistoryRetention,
                style: context.theme.typography.bodySmall.onSurfaceVariant,
                textAlign: .center,
              ),
            ),
            Expanded(child: _buildHistory(context)),
          ],
        ),
      ),
    ),
  );

  Widget _buildHistory(BuildContext context) {
    final l10n = context.l10n;
    if (_versions.isEmpty) {
      if (_loading) return const MLoading();
      if (_loadFailed) return _loadError(context);
      return Center(child: Text(l10n.diary.versionHistoryEmpty));
    }
    return ListView.builder(
      itemCount: _versions.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _versions.length) {
          return Padding(
            padding: const .all(12),
            child: _loading
                ? const MLoading()
                : _loadFailed
                ? _loadError(context)
                : Center(
                    child: TextButton(
                      onPressed: _busy ? null : _loadMore,
                      child: Text(l10n.diary.versionHistoryMore),
                    ),
                  ),
          );
        }
        final version = _versions[index];
        final diary = version.diary;
        return ListTile(
          title: Text(
            diary.title.trim().isEmpty ? l10n.common.untitled : diary.title,
            maxLines: 1,
            overflow: .ellipsis,
          ),
          subtitle: Text(TimeFormat.fullDateTime(diary.lastModified)),
          trailing: Row(
            mainAxisSize: .min,
            children: [
              IconButton(
                tooltip: l10n.diary.versionHistoryRestore,
                icon: const Icon(LucideIcons.undo2),
                onPressed: _busy
                    ? null
                    : () => _perform((context) => _restore(context, version)),
              ),
              IconButton(
                tooltip: l10n.diary.versionHistoryDelete,
                icon: const Icon(LucideIcons.trash2),
                onPressed: _busy
                    ? null
                    : () => _perform(
                        (context) => _delete(context, version: version),
                      ),
              ),
            ],
          ),
          onTap: _busy ? null : () => _openVersion(version),
        );
      },
    );
  }

  Widget _loadError(BuildContext context) => Center(
    child: Column(
      mainAxisSize: .min,
      children: [
        Text(context.l10n.common.loadFailed),
        TextButton(
          onPressed: _loadMore,
          child: Text(context.l10n.common.retry),
        ),
      ],
    ),
  );
}

class _DiaryVersionPreview extends StatefulWidget {
  final Diary version;
  final _VersionAction onRestore;
  final _VersionAction onDelete;

  const _DiaryVersionPreview({
    required this.version,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  State<_DiaryVersionPreview> createState() => _DiaryVersionPreviewState();
}

class _DiaryVersionPreviewState extends State<_DiaryVersionPreview> {
  bool _acting = false;

  Future<void> _perform(_VersionAction action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final result = await action(context);
      if (result != .unchanged &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    return PopScope<_VersionResult>(
      canPop: !_acting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            TimeFormat.fullDateTime(version.lastModified),
            maxLines: 1,
            overflow: .ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: _acting ? null : () => _perform(widget.onRestore),
              tooltip: context.l10n.diary.versionHistoryRestore,
              icon: const Icon(LucideIcons.undo2),
            ),
            IconButton(
              onPressed: _acting ? null : () => _perform(widget.onDelete),
              style: IconButton.styleFrom(
                foregroundColor: context.theme.colors.error,
              ),
              tooltip: context.l10n.diary.versionHistoryDelete,
              icon: const Icon(LucideIcons.trash2),
            ),
          ],
        ),
        body: SafeArea(
          child: EditorBody(
            type: .fromValue(version.type),
            initialTitle: version.title,
            initialContent: version.content,
            editable: false,
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
  }
}
