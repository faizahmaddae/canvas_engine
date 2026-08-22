import '../../../../l10n/app_localizations.dart';

/// One relative-time voice for every surface that stamps a project
/// with "when": the Projects-tab grid card and Home's continue hero.
/// Hoisted out of the grid so the two cannot drift into disagreeing
/// about what «دیروز» means.
String relativeTime(AppLocalizations l10n, DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24 && now.day == t.day) return l10n.hoursAgo(diff.inHours);
  if (diff.inDays < 2) return l10n.yesterday;
  if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.weeksAgo((diff.inDays / 7).floor());
  return l10n.monthsAgo((diff.inDays / 30).floor());
}
