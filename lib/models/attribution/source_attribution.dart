import 'package:freezed_annotation/freezed_annotation.dart';

part 'source_attribution.freezed.dart';
part 'source_attribution.g.dart';

/// Credit a source owes where its content is played or viewed: who made it,
/// where it lives, and under which licence. Dharma Seed's CC BY-NC-ND terms
/// need exactly this; any later source with a licence fills it the same way.
@freezed
abstract class SourceAttribution with _$SourceAttribution {
  const factory SourceAttribution({
    /// The catalogue, e.g. "Dharma Seed".
    required String source,

    /// The teacher or author, when known.
    String? creator,

    /// The item's own page on the source's site.
    required String url,
    required String licenseName,
    required String licenseUrl,
  }) = _SourceAttribution;

  factory SourceAttribution.fromJson(Map<String, Object?> json) =>
      _$SourceAttributionFromJson(json);
}
