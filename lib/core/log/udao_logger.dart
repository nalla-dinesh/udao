import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../constants/app_constants.dart';
import '../utils/date_utils.dart';

/// Severity-ordered log levels.
enum LogLevel { trace, debug, info, warn, error, fatal }

/// One immutable log record. [timestamp] follows the IST convention
/// (see `IstDates`).
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.message,
    this.error,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String scope;
  final String message;
  final Object? error;

  Map<String, Object?> toMap() => <String, Object?>{
        'ts': IstDates.isoDateTime(timestamp),
        'level': level.name,
        'scope': scope,
        'message': message,
        if (error != null) 'error': error.toString(),
      };

  String toJsonLine() => jsonEncode(toMap());
}

class _SinkState {
  IOSink? sink;
  String? path;
  int bytesWritten = 0;
  int maxBytes = 512 * 1024;
  int backups = 3;
  bool broken = false;
}

/// UDAO logger: in-memory ring buffer (default 500 entries) plus an
/// optional JSONL file sink with size-based rotation.
///
/// Logging must NEVER crash the app — every sink error is swallowed
/// after flagging the sink broken. Single-isolate by design (Phase 03's
/// native WAL covers events that happen while the Flutter engine is
/// down).
///
/// There is no `print` anywhere in UDAO; `avoid_print` is enforced by
/// analysis_options.yaml.
class UdaoLogger {
  UdaoLogger({
    int ringCapacity = AppConstants.logRingCapacity,
    String scope = 'udao',
  }) : this._(
          ringCapacity,
          scope,
          ListQueue<LogEntry>(ringCapacity),
          _SinkState(),
        );

  UdaoLogger._(
    this._ringCapacity,
    this._scope,
    this._ring,
    this._sinkState,
  );

  final int _ringCapacity;
  final String _scope;
  final ListQueue<LogEntry> _ring;
  final _SinkState _sinkState;

  void trace(String message) => _log(LogLevel.trace, message);

  void debug(String message) => _log(LogLevel.debug, message);

  void info(String message) => _log(LogLevel.info, message);

  void warn(String message) => _log(LogLevel.warn, message);

  void error(String message, {Object? error}) =>
      _log(LogLevel.error, message, error: error);

  void fatal(String message, {Object? error}) =>
      _log(LogLevel.fatal, message, error: error);

  /// A scoped child that SHARES this logger's ring buffer and file
  /// sink (`udaoLog.child('capture')` logs with scope `udao.capture`).
  UdaoLogger child(String childScope) => UdaoLogger._(
        _ringCapacity,
        '$_scope.$childScope',
        _ring,
        _sinkState,
      );

  /// Read-only view of the current buffer, oldest first.
  List<LogEntry> snapshot() => List<LogEntry>.unmodifiable(_ring);

  /// Most recent entry, if any.
  LogEntry? get lastEntry => _ring.isEmpty ? null : _ring.last;

  /// Empties the ring buffer (file sink untouched).
  void clear() => _ring.clear();

  /// Attaches a JSONL file sink at the path [pathResolver] returns.
  /// Rotates at [maxBytes] keeping [backups] old files (`.1`, `.2`, …).
  ///
  /// The resolver is injected so unit tests never touch path_provider;
  /// the app layer resolves a real directory (Phase 02 wires it up).
  Future<void> attachFileSink(
    String Function() pathResolver, {
    int maxBytes = 512 * 1024,
    int backups = 3,
  }) async {
    if (_sinkState.broken) {
      return;
    }
    try {
      final path = pathResolver();
      final file = File(path);
      await file.create(recursive: true);
      _sinkState
        ..path = path
        ..maxBytes = maxBytes
        ..backups = backups
        ..sink = file.openWrite(mode: FileMode.append);
    } on Object {
      // Logging must never take the app down.
      _sinkState.broken = true;
    }
  }

  /// Flushes and closes the file sink (app teardown).
  Future<void> close() async {
    final sink = _sinkState.sink;
    _sinkState.sink = null;
    if (sink != null) {
      try {
        await sink.flush();
        await sink.close();
      } on Object {
        // Already detached; nothing else to do.
      }
    }
  }

  void _log(LogLevel level, String message, {Object? error}) {
    final entry = LogEntry(
      timestamp: IstDates.nowIst(),
      level: level,
      scope: _scope,
      message: message,
      error: error,
    );
    _ring.addLast(entry);
    while (_ring.length > _ringCapacity) {
      _ring.removeFirst();
    }
    _writeToSink(entry);
  }

  void _writeToSink(LogEntry entry) {
    final sink = _sinkState.sink;
    if (sink == null || _sinkState.broken) {
      return;
    }
    try {
      final line = '${entry.toJsonLine()}\n';
      sink.write(line);
      _sinkState.bytesWritten += line.length;
      if (_sinkState.bytesWritten >= _sinkState.maxBytes) {
        unawaited(_rotate());
      }
    } on Object {
      _sinkState.broken = true;
    }
  }

  Future<void> _rotate() async {
    final sink = _sinkState.sink;
    final path = _sinkState.path;
    if (sink == null || path == null || _sinkState.broken) {
      return;
    }
    try {
      await sink.flush();
      await sink.close();
      for (var i = _sinkState.backups - 1; i >= 1; i--) {
        final from = File('$path.$i');
        if (from.existsSync()) {
          from.renameSync('$path.${i + 1}');
        }
      }
      File(path).renameSync('$path.1');
      _sinkState.bytesWritten = 0;
      _sinkState.sink = File(path).openWrite(mode: FileMode.append);
    } on Object {
      _sinkState.broken = true;
    }
  }
}

/// The app-wide logger instance. Use `udaoLog.child('feature')` inside
/// features; never construct parallel loggers.
final UdaoLogger udaoLog = UdaoLogger();
