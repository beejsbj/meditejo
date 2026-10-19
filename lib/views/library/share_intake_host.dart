import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/import_providers.dart';
import 'package:medito/services/library/share_intake.dart';
import 'package:medito/views/library/import_view.dart';

/// Sends a link or audio file shared into the app straight to the import
/// screen, previewed and ready to add. Wraps the main screen so it is there
/// for the share that started the app and for shares that arrive later.
class ShareIntakeHost extends ConsumerStatefulWidget {
  const ShareIntakeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareIntakeHost> createState() => _ShareIntakeHostState();
}

class _ShareIntakeHostState extends ConsumerState<ShareIntakeHost> {
  StreamSubscription<SharedPayload>? _subscription;

  @override
  void initState() {
    super.initState();
    final intake = ref.read(shareIntakeProvider);
    _subscription = intake.shares.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await intake.initial();
      if (initial != null && mounted) _open(initial);
    });
  }

  void _open(SharedPayload payload) {
    if (!mounted || payload.isEmpty) return;
    unawaited(
      openImport(context, ref, text: payload.text, files: payload.files),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
