import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/widgets/add_to_library_icon.dart';

/// Single sessions as the same rows a course page uses: kind, title, teacher
/// and length, with their played and downloaded state. Tapping opens the
/// session's own page, where the credit and licence are shown.
class SessionRowsSliver extends ConsumerWidget {
  const SessionRowsSliver({
    super.key,
    required this.items,
    this.onBeforeNavigate,
  });

  final List<PackItemsModel> items;

  /// Runs before a row navigates, e.g. to dismiss the keyboard.
  final VoidCallback? onBeforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Column(
          key: ValueKey('session_${item.id}'),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    child: InkWell(
                      onTap: () {
                        onBeforeNavigate?.call();
                        handleNavigation(
                          TypeConstants.track,
                          [item.id, item.path],
                          context,
                          ref: ref,
                        );
                      },
                      child: PackItemWidget(item: item),
                    ),
                  ),
                ),
                AddToLibraryIcon(id: item.id),
                ContentActionsButton(
                  id: item.id,
                  fallback: MyItemDraft.fromPackItem(item),
                ),
              ],
            ),
            if (index < items.length - 1)
              const Divider(
                color: ColorConstants.charcoal,
                thickness: 0.5,
                height: 1,
              ),
          ],
        );
      },
    );
  }
}
