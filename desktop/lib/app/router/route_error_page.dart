import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

class RouteErrorPage extends StatelessWidget {
  final Uri uri;
  final Exception? error;

  const RouteErrorPage({super.key, required this.uri, this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.compass,
              size: 48,
              color: context.theme.colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.app.routeErrorTitle,
              style: context.theme.typography.titleMedium.emphasized.onSurface,
            ),
            const SizedBox(height: 8),
            Text(uri.toString(), textAlign: TextAlign.center),
            if (kDebugMode && error != null) ...[
              const SizedBox(height: 8),
              Text('$error', style: context.theme.typography.bodySmall.error),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => const DiaryHomeRoute().go(context),
              child: Text(context.l10n.app.routeErrorBackHome),
            ),
          ],
        ),
      ),
    ),
  );
}
