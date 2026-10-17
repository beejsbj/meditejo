import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_widgets.dart';
import 'package:medito/widgets/filter_pill.dart';
import 'package:medito/widgets/medito_icon.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// A few starting points shown before anything is typed. They are Burooj's
/// own material (see docs/fork/BRIEF.md), not a ranking of Dharma Seed.
const searchSuggestions = ['Rob Burbea', 'metta', 'jhana', 'emptiness'];

extension SessionLengthLabel on SessionLength {
  String label(AppLocalizations l10n) => switch (this) {
    SessionLength.under10 => l10n.searchLengthUnder10,
    SessionLength.from10to20 => l10n.searchLength10to20,
    SessionLength.from20to30 => l10n.searchLength20to30,
    SessionLength.from30to45 => l10n.searchLength30to45,
    SessionLength.over45 => l10n.searchLengthOver45,
  };
}

/// Search results for [query]: suggestions while empty, otherwise results
/// grouped as Teachers, Courses and Talks (teachers lead, because a talk that
/// quotes a teacher can outrank the teacher's own), with a session-length
/// filter that narrows the talks.
class SearchResults extends ConsumerStatefulWidget {
  const SearchResults({
    super.key,
    required this.query,
    this.onBeforeNavigate,
    this.onSuggestion,
  });

  final String query;

  /// Runs before a result navigates, e.g. to dismiss the keyboard.
  final VoidCallback? onBeforeNavigate;

  /// Called with a suggestion the user tapped on the empty page.
  final ValueChanged<String>? onSuggestion;

  @override
  ConsumerState<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<SearchResults> {
  SessionLength? _length;

  /// The last results shown, kept on screen while the next query or filter
  /// loads so the page does not blink.
  DsSearchResults? _shown;

  @override
  void didUpdateWidget(covariant SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query.trim().isEmpty) _shown = null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: widget.query.trim().isEmpty
          ? [_buildEmptyState()]
          : _buildResults(),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(padding24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MeditoIcon(
                assetName: MeditoIcons.search,
                size: 32,
                color: theme.colorScheme.onSurface.withOpacityValue(0.3),
              ),
              const SizedBox(height: padding12),
              Text(
                l10n.searchTryHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacityValue(0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: padding16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: padding8,
                runSpacing: padding8,
                children: [
                  for (final suggestion in searchSuggestions)
                    FilterPill(
                      key: ValueKey('suggestion_$suggestion'),
                      label: suggestion,
                      selected: false,
                      onTap: () => widget.onSuggestion?.call(suggestion),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResults() {
    final query = widget.query.trim();
    final async = ref.watch(
      dharmaSeedSearchProvider((query: query, length: _length)),
    );
    if (async.hasValue) _shown = async.value;
    final results = _shown;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (results == null) {
      if (async.hasError) {
        final err = async.error;
        return [
          SliverFillRemaining(
            child: MeditoErrorWidget(
              error: err is AppError ? err : const UnknownError(),
              isScaffold: false,
              onTap: () => ref.invalidate(dharmaSeedSearchProvider),
            ),
          ),
        ];
      }
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }

    final nothing =
        results.teachers.isEmpty &&
        results.courses.isEmpty &&
        results.talks.isEmpty &&
        _length == null;
    if (nothing) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(padding16),
              child: Text(
                l10n.noResultsFound,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacityValue(0.7),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      if (results.teachers.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: l10n.searchTeachers)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: padding8),
            child: TeacherRows(
              teachers: results.teachers,
              onBeforeNavigate: widget.onBeforeNavigate,
            ),
          ),
        ),
      ],
      if (results.courses.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: l10n.searchCourses)),
        const SliverPadding(padding: EdgeInsets.only(top: padding8)),
        CourseRowsSliver(
          courses: results.courses,
          onBeforeNavigate: widget.onBeforeNavigate,
        ),
      ],
      SliverToBoxAdapter(child: SectionHeader(title: l10n.searchTalks)),
      SliverToBoxAdapter(child: _lengthFilter(l10n)),
      if (results.talks.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(padding16),
            child: Text(
              l10n.noResultsFound,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacityValue(0.7),
              ),
            ),
          ),
        )
      else
        SessionRowsSliver(
          items: results.talks,
          onBeforeNavigate: widget.onBeforeNavigate,
        ),
      SliverPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 96,
        ),
      ),
    ];
  }

  /// Any, under 10, 10–20, 20–30, 30–45 and over 45 minutes. It narrows the
  /// talks only; teachers and courses have no length.
  Widget _lengthFilter(AppLocalizations l10n) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: padding16,
          vertical: padding8,
        ),
        children: [
          FilterPill(
            key: const ValueKey('length_any'),
            label: l10n.searchLengthAny,
            selected: _length == null,
            onTap: () => setState(() => _length = null),
          ),
          for (final length in SessionLength.values) ...[
            const SizedBox(width: padding8),
            FilterPill(
              key: ValueKey('length_${length.name}'),
              label: length.label(l10n),
              selected: _length == length,
              onTap: () =>
                  setState(() => _length = _length == length ? null : length),
            ),
          ],
        ],
      ),
    );
  }
}
