import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';

/// dhammatalks.org under Settings' Sources. It ships as a snapshot and reads
/// its feeds quietly, so there is nothing to sync or set: the row says what
/// it is and opens its one teacher's page, where its talks are.
class DhammatalksSourceTile extends ConsumerWidget {
  const DhammatalksSourceTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return RowItemWidget(
      key: const ValueKey('settings_source_dhammatalks'),
      icon: Icon(
        Icons.library_music_outlined,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      // The source's own name, as the Library's cards give it.
      title: 'dhammatalks.org',
      subTitle: l10n.settingsDhammatalksCaption(dtTeacherName),
      hasUnderline: hasUnderline,
      onTap: () => handleNavigation(
        TypeConstants.teacher,
        [dtTeacherId],
        context,
        ref: ref,
      ),
    );
  }
}
