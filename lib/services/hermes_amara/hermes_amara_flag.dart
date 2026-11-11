/// Whether the Hermes Amāra Foundation adapter may run at all.
///
/// Off by default and in every release build. hermesamara.org states no
/// licence, and permission has been asked for but not given, so the whole
/// adapter is dormant: nothing is fetched, listed, played or saved. Turning
/// it on later is building with `--dart-define=MEDITEJO_HERMES_AMARA=true`
/// (and flipping the default here if wanted), once Burooj has permission.
const bool hermesAmaraEnabled = bool.fromEnvironment('MEDITEJO_HERMES_AMARA');
