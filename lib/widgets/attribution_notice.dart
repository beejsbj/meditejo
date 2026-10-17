import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/utils/utils.dart';

/// The credit a licence asks for, wherever its content is played or viewed:
/// who made it and where it lives, the licence, and (in the full form) a note
/// that the audio is streamed unmodified. Both links open in the browser.
class AttributionNotice extends StatelessWidget {
  const AttributionNotice({
    super.key,
    required this.attribution,
    this.compact = false,
    this.color,
    this.alignment = CrossAxisAlignment.start,
    this.padding = EdgeInsets.zero,
  });

  final SourceAttribution attribution;

  /// One wrapped line without the unmodified note, for the player.
  final bool compact;

  /// Overrides the theme's muted text colour, e.g. white over the player.
  final Color? color;

  final CrossAxisAlignment alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final base =
        color ?? theme.colorScheme.onSurface.withOpacityValue(0.7);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: base,
      fontSize: compact ? 12 : 13,
      height: 1.4,
    );
    final credit = [
      if (attribution.creator case final creator? when creator.isNotEmpty)
        creator,
      attribution.source,
    ].join(' · ');
    final licence = compact
        ? attribution.licenseName
        : l10n.attributionLicence(attribution.licenseName);

    Widget link(String text, String url, {String? semanticLabel}) => Semantics(
      link: true,
      label: semanticLabel ?? text,
      excludeSemantics: true,
      onTap: () => launchURLInBrowser(url),
      child: InkWell(
        onTap: () => launchURLInBrowser(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text,
            style: style?.copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
    );

    final creditLink = link(
      credit,
      attribution.url,
      semanticLabel:
          '$credit. ${l10n.attributionViewOn(attribution.source)}',
    );
    final licenceLink = link(licence, attribution.licenseUrl);

    return Padding(
      padding: padding,
      child: compact
          ? Wrap(
              alignment: alignment == CrossAxisAlignment.center
                  ? WrapAlignment.center
                  : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [creditLink, Text('·', style: style), licenceLink],
            )
          : Column(
              crossAxisAlignment: alignment,
              children: [
                creditLink,
                licenceLink,
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(l10n.attributionUnmodified, style: style),
                ),
              ],
            ),
    );
  }
}
