import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

class TagRenameSheet extends StatefulWidget {
  final String tag;
  final Future<String?> Function(String value) onSubmit;

  const TagRenameSheet({super.key, required this.tag, required this.onSubmit});

  @override
  State<TagRenameSheet> createState() => _TagRenameSheetState();
}

class _TagRenameSheetState extends State<TagRenameSheet> {
  late final _controller = TextEditingController(text: widget.tag);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final value = TagPath.normalize(_controller.text);
    if (value == null || !TagPath.isInline(value)) {
      setState(() => _error = context.l10n.diary.tagInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      failure = await widget.onSubmit(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = failure);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: MSheetScaffold<void>(
      title: context.l10n.diary.tagRename,
      icon: LucideIcons.pencil,
      actions: [
        MAction(label: context.l10n.common.cancel, enabled: !_busy),
        MAction(
          label: context.l10n.common.ok,
          isPrimary: true,
          enabled: !_busy,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
      child: MField(
        controller: _controller,
        autofocus: true,
        hintText: context.l10n.diary.tagRenameHint,
        errorText: _error,
        enabled: !_busy,
        onSubmitted: (_) => _submit(),
      ),
    ),
  );
}
