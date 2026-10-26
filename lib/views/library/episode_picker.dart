import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/views/library/library_format.dart';

/// Lists longer than this get a search field.
const episodeSearchThreshold = 12;

const _rowExtent = 68.0;

/// "12 Mar 2026 · 45 min" (whatever of it is known), with "Latest" first for
/// a feed's newest episode.
String episodeDetail(
  BuildContext context,
  ImportEpisode episode, {
  bool latest = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final date = episode.publishedAt;
  final length = episode.durationMs;
  return [
    if (latest) l10n.importEpisodeLatest,
    if (date != null)
      DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date),
    if (length != null && length > 0) formatLongDuration(length),
  ].join(' · ');
}

/// Asks which episode of a list to add. [episodes] come in the order to show
/// them (a feed's newest first). Returns the picked episode's ID, or null.
Future<String?> showEpisodePicker(
  BuildContext context, {
  required List<ImportEpisode> episodes,
  required String? selectedId,
  String? latestId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => EpisodePickerSheet(
    episodes: episodes,
    selectedId: selectedId,
    latestId: latestId,
  ),
);

class EpisodePickerSheet extends StatefulWidget {
  const EpisodePickerSheet({
    super.key,
    required this.episodes,
    required this.selectedId,
    this.latestId,
  });

  final List<ImportEpisode> episodes;
  final String? selectedId;

  /// The episode to mark "Latest", for a feed.
  final String? latestId;

  @override
  State<EpisodePickerSheet> createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<EpisodePickerSheet> {
  final _query = TextEditingController();
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Open with the current choice in view, not at the top of a long list.
    final at = widget.episodes.indexWhere((e) => e.id == widget.selectedId);
    _scroll = ScrollController(
      initialScrollOffset: at > 1 ? (at - 1) * _rowExtent : 0,
    );
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ImportEpisode> get _shown {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.episodes;
    return [
      for (final e in widget.episodes)
        if (e.title.toLowerCase().contains(needle)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final shown = _shown;
    final searchable = widget.episodes.length > episodeSearchThreshold;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.importEpisodePickerTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const ValueKey('episode_search'),
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.importEpisodeSearch,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      l10n.importEpisodeNone,
                      key: const ValueKey('episode_none'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowExtent,
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final episode = shown[index];
                      final selected = episode.id == widget.selectedId;
                      return ListTile(
                        key: ValueKey('episode_${episode.id}'),
                        selected: selected,
                        title: Text(
                          episode.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          episodeDetail(
                            context,
                            episode,
                            latest: episode.id == widget.latestId,
                          ),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, episode.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
