// phase-03
// One raw notification capture, exactly as the native layer wrote it
// to the WAL / pushed to the live stream. Parsing happens DOWNSTREAM
// (Dart pipeline) — this type is transport, not interpretation.
import 'dart:convert';

class CaptureRawEvent {
  const CaptureRawEvent({
    required this.pkg,
    required this.title,
    required this.text,
    required this.bigText,
    required this.subText,
    required this.ts,
  });

  /// Android package (`com.phonepe.app`, …).
  final String pkg;
  final String title;
  final String text;
  final String bigText;
  final String subText;

  /// Device wall-clock epoch ms of the notification post.
  final int ts;

  /// Parser-facing body: title first, then the long form (bigText
  /// preferred over text), then any sub-text. UPI apps split the
  /// sentence across these fields, so the parsers get the full text.
  String get fullText {
    final List<String> parts = <String>[
      if (title.isNotEmpty) title,
      if (bigText.isNotEmpty) bigText else if (text.isNotEmpty) text,
      if (subText.isNotEmpty) subText,
    ];
    return parts.join('\n');
  }

  /// When the event landed on the device.
  DateTime get receivedAt => DateTime.fromMillisecondsSinceEpoch(ts);

  /// SMS sender address when this event came from the power-flavor
  /// SMS receiver (native layer encodes it in [pkg] as
  /// `sms:<SENDER>`), null for app notifications. The bank parsers
  /// match on this sender tag; OtpFilter and everything downstream
  /// are sender-agnostic.
  String? get sender =>
      pkg.startsWith('sms:') && pkg.length > 4 ? pkg.substring(4) : null;

  /// Parses one WAL/livestream JSON line; null on malformed input
  /// (torn writes must never crash the replay).
  static CaptureRawEvent? fromLine(String line) {
    try {
      final Map<String, Object?> json =
          jsonDecode(line) as Map<String, Object?>;
      final Object? pkg = json['pkg'];
      final Object? ts = json['ts'];
      if (pkg is! String || ts is! int) {
        return null;
      }
      return CaptureRawEvent(
        pkg: pkg,
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        bigText: json['bigText'] as String? ?? '',
        subText: json['subText'] as String? ?? '',
        ts: ts,
      );
    } on Object {
      return null;
    }
  }

  /// The exact WAL line shape (round-trips through [fromLine]).
  String toLine() => jsonEncode(<String, Object?>{
        'pkg': pkg,
        'title': title,
        'text': text,
        'bigText': bigText,
        'subText': subText,
        'ts': ts,
      });
}
