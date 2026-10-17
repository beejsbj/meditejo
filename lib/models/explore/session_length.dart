/// The session-length buckets of the search filter, in whole minutes:
/// under 10, 10–20, 20–30, 30–45 and over 45.
enum SessionLength {
  under10(null, 10),
  from10to20(10, 20),
  from20to30(20, 30),
  from30to45(30, 45),
  over45(45, null);

  const SessionLength(this.minMinutes, this.maxMinutes);

  /// Inclusive lower bound; null when open.
  final int? minMinutes;

  /// Exclusive upper bound; null when open.
  final int? maxMinutes;

  Duration? get min =>
      minMinutes == null ? null : Duration(minutes: minMinutes!);

  Duration? get max =>
      maxMinutes == null ? null : Duration(minutes: maxMinutes!);

  bool matches(Duration length) =>
      (min == null || length >= min!) && (max == null || length < max!);
}
