import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_ml/moodiary_ml.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:mui/mui.dart';

/// Displays an accounting snapshot of the application's local files.
class StoragePage extends StatefulWidget {
  const StoragePage({
    super.key,
    this.onManageModels,
    this.loadUsage,
    this.cleanDownloads,
  });

  final Future<void> Function()? onManageModels;

  @visibleForTesting
  final Future<StorageUsage> Function()? loadUsage;

  @visibleForTesting
  final Future<ModelPartialCleanup> Function()? cleanDownloads;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  late Future<StorageUsage> _usage;
  bool _cleaning = false;
  String? _cleanupMessage;

  @override
  void initState() {
    super.initState();
    _usage = _beginScan();
  }

  Future<StorageUsage> _scan() async {
    final load = widget.loadUsage;
    if (load != null) return load();
    final platform = PlatformService.get();
    return StorageScanner(
      supportPath: platform.applicationSupportPath,
      cachePath: platform.applicationCachePath,
    ).scan();
  }

  Future<StorageUsage> _beginScan() {
    final future = _scan();
    // A fast failure can occur before FutureBuilder subscribes on the next
    // frame. It still receives and displays the original future's error.
    future.ignore();
    return future;
  }

  void _retry() => setState(() {
    _usage = _beginScan();
  });

  Future<void> _manageModels() async {
    await widget.onManageModels?.call();
    if (mounted) _retry();
  }

  Future<void> _cleanDownloads() async {
    final text = context.l10n.storage;
    final confirmed = await MAlert.confirm(
      context,
      title: text.cleanDownloads,
      message: text.cleanDownloadsDescription,
      confirmLabel: text.cleanConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _cleaning = true;
      _cleanupMessage = null;
    });
    try {
      final clean =
          widget.cleanDownloads ??
          getIt<EmbeddingModelManager>().cleanIncompleteDownloads;
      final result = await clean();
      if (!mounted) return;
      final size = _size(result.deletedBytes);
      _cleanupMessage = result.failedFiles == 0
          ? text.cleanDone(count: result.deletedFiles, size: size)
          : text.cleanPartial(
              count: result.deletedFiles,
              size: size,
              failed: result.failedFiles,
            );
      if (result.failedFiles == 0) {
        toast.success(message: _cleanupMessage);
      } else {
        toast.error(message: _cleanupMessage);
      }
    } catch (_) {
      if (!mounted) return;
      _cleanupMessage = text.cleanFailed;
      toast.error(message: _cleanupMessage);
    } finally {
      if (mounted) {
        setState(() {
          _cleaning = false;
          _usage = _beginScan();
        });
      }
    }
  }

  String _size(int bytes) {
    final value = AppFiles.bytesToUnits(bytes);
    return '${value['size']} ${value['unit']}';
  }

  @override
  Widget build(BuildContext context) {
    final text = context.l10n.storage;
    return Scaffold(
      appBar: AppBar(title: Text(text.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: FutureBuilder<StorageUsage>(
            future: _usage,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      Text(text.failed),
                      TextButton(onPressed: _retry, child: Text(text.retry)),
                      if (_cleanupMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(_cleanupMessage!),
                        ),
                    ],
                  ),
                );
              }
              final usage = snapshot.data;
              if (usage == null) {
                return Center(
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(text.loading),
                    ],
                  ),
                );
              }
              final bytes = usage.bytesByCategory;
              int sizeOf(StorageCategory category) => bytes[category] ?? 0;
              final rows = <({String label, int bytes})>[
                (label: text.database, bytes: sizeOf(.database)),
                (
                  label: text.media,
                  bytes: sizeOf(.image) + sizeOf(.audio) + sizeOf(.video),
                ),
                (label: text.model, bytes: sizeOf(.model)),
                (label: text.font, bytes: sizeOf(.font)),
                (label: text.logs, bytes: sizeOf(.logs)),
                (label: text.cache, bytes: sizeOf(.cache)),
                (label: text.other, bytes: sizeOf(.other)),
              ];
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            text.used,
                            style: context
                                .theme
                                .typography
                                .bodyMedium
                                .onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _size(usage.totalBytes),
                            style: context
                                .theme
                                .typography
                                .headlineMedium
                                .onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
                  MSliverSettingGroup(
                    children: [
                      for (final row in rows)
                        SettingListTile(
                          title: row.label,
                          trailing: Text(_size(row.bytes)),
                        ),
                    ],
                  ),
                  MSliverSettingGroup(
                    children: [
                      SettingListTile(
                        title: text.cleanDownloads,
                        subtitle: _cleaning
                            ? text.cleaning
                            : text.cleanDownloadsDescription,
                        onTap: _cleaning ? null : _cleanDownloads,
                      ),
                      if (widget.onManageModels != null)
                        SettingListTile(
                          title: text.manageModels,
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: _manageModels,
                        ),
                    ],
                  ),
                  if (_cleanupMessage != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text(_cleanupMessage!),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
