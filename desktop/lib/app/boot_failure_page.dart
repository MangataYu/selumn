import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

class BootFailurePage extends StatelessWidget {
  final Object error;

  const BootFailurePage({super.key, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildMuiTheme(brightness: Brightness.light),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.triangleAlert, size: 40),
                const SizedBox(height: 16),
                Text(l10n.app.routeErrorTitle),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(child: SelectableText('$error')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
