import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/services/categories/entry_labels.dart';

/// Opens the sheet where the user sets a library item's categories and adds
/// labels of their own. [title] is what the item is called in the library;
/// the app's guesses are made from it (and, for Dharma Seed, from its
/// description).
Future<void> showLabelsSheet(
  BuildContext context, {
  required String id,
  required String title,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => LabelsSheet(subject: (id: id, title: title), heading: title),
);

/// Categories as chips (ticked when the item has them, by the app's guess or
/// the user's choice), then the user's own labels with a field to add one.
/// The user's word always wins: ticking a category pins it, and unticking a
/// guessed one removes it for good.
class LabelsSheet extends ConsumerStatefulWidget {
  const LabelsSheet({super.key, required this.subject, required this.heading});

  final LabelSubject subject;
  final String heading;

  @override
  ConsumerState<LabelsSheet> createState() => _LabelsSheetState();
}

class _LabelsSheetState extends ConsumerState<LabelsSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text;
    _controller.clear();
    final service = await ref.read(categoryServiceProvider.future);
    await service.addLabel(widget.subject.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    final catalogue = ref.watch(categoryCatalogueProvider).value;
    final labels =
        ref.watch(labelsOfProvider(widget.subject)).value ?? EntryLabels.none;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.labelsTitle, style: type.emphasized.titleLarge),
            ),
            const SizedBox(height: 4),
            Text(
              widget.heading,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: type.baseline.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (catalogue != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in catalogue.categories)
                    FilterChip(
                      key: ValueKey('labels_category_${category.id}'),
                      label: Text(category.name),
                      selected: labels.hasCategory(category.id),
                      onSelected: (on) async {
                        final service = await ref.read(
                          categoryServiceProvider.future,
                        );
                        await service.setCategory(
                          widget.subject.id,
                          category.id,
                          on: on,
                          current: labels,
                          title: widget.subject.title,
                        );
                      },
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              l10n.labelsExplain,
              style: type.baseline.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (labels.custom.isNotEmpty) ...[
              Semantics(
                header: true,
                child: Text(
                  l10n.labelsCustomHeading,
                  style: type.emphasized.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in labels.custom)
                    InputChip(
                      key: ValueKey('labels_custom_$text'),
                      label: Text(text),
                      deleteButtonTooltipMessage: l10n.labelsRemoveTooltip(
                        text,
                      ),
                      onDeleted: () async {
                        final service = await ref.read(
                          categoryServiceProvider.future,
                        );
                        await service.removeCustomLabel(
                          widget.subject.id,
                          text,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('labels_field'),
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: l10n.labelsAddHint),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  key: const ValueKey('labels_add'),
                  onPressed: _add,
                  child: Text(l10n.labelsAddButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
