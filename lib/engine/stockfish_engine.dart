import 'dart:async';

import 'package:stockfish_flutter_plus/stockfish_flutter_plus.dart';

import '../analysis/models.dart';

/// Wraps the Stockfish engine bundled inside the app (via FFI).
/// The plugin only allows one engine at a time, so use [shared].
class StockfishEngine implements EngineAnalyzer {
  StockfishEngine._();

  static StockfishEngine? _instance;
  static Future<StockfishEngine>? _starting;

  static StockfishEngine? get instanceOrNull => _instance;

  static Future<StockfishEngine> shared() {
    if (_instance != null) return Future.value(_instance!);
    return _starting ??= _create();
  }

  static Future<StockfishEngine> _create() async {
    final engine = StockfishEngine._();
    try {
      await engine._start();
      _instance = engine;
      return engine;
    } catch (_) {
      _starting = null;
      engine._abort();
      rethrow;
    }
  }

  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  Completer<void>? _uciOk;
  Completer<void>? _readyOk;
  Completer<List<EngineLine>>? _pending;
  final Map<int, EngineLine> _lines = {};
  int _multiPv = 3;

  Future<void> _start() async {
    final sf = Stockfish();
    _sf = sf;
    final started = DateTime.now();
    while (sf.state.value != StockfishState.ready) {
      if (sf.state.value == StockfishState.error) {
        throw StateError('The chess engine could not start on this device.');
      }
      if (DateTime.now().difference(started) > const Duration(seconds: 30)) {
        throw TimeoutException('The chess engine took too long to start.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _sub = sf.stdout.listen(_onLine);

    _uciOk = Completer<void>();
    sf.stdin = 'uci';
    await _uciOk!.future.timeout(const Duration(seconds: 15));

    sf.stdin = 'setoption name Threads value 4';
    sf.stdin = 'setoption name Hash value 64';
    sf.stdin = 'setoption name MultiPV value 3';
    _multiPv = 3;
    await _waitReady();
  }

  Future<void> _waitReady() async {
    final sf = _sf!;
    _readyOk = Completer<void>();
    sf.stdin = 'isready';
    await _readyOk!.future.timeout(const Duration(seconds: 15));
  }

  void _abort() {
    try {
      _sub?.cancel();
      if (_sf != null && _sf!.state.value == StockfishState.ready) {
        _sf!.dispose();
      }
    } catch (_) {}
    _sf = null;
  }

  Future<void> _waitIdle() async {
    int guard = 0;
    while (_pending != null && guard < 400) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      guard++;
    }
  }

  /// Clears the engine's memory between games.
  Future<void> newGame() async {
    await _waitIdle();
    _sf!.stdin = 'ucinewgame';
    await _waitReady();
  }

  /// Interrupts a running search (the pending analysis still completes).
  void stop() {
    try {
      if (_pending != null && _sf != null) _sf!.stdin = 'stop';
    } catch (_) {}
  }

  @override
  Future<List<EngineLine>> analyze(String fen,
      {int? movetimeMs, int? depth, int multiPv = 3}) async {
    await _waitIdle();
    final sf = _sf;
    if (sf == null) throw StateError('Engine is not running.');
    _lines.clear();
    if (multiPv != _multiPv) {
      sf.stdin = 'setoption name MultiPV value $multiPv';
      _multiPv = multiPv;
    }
    final completer = Completer<List<EngineLine>>();
    _pending = completer;
    sf.stdin = 'position fen $fen';
    sf.stdin = depth != null ? 'go depth $depth' : 'go movetime ${movetimeMs ?? 500}';
    final limit = depth != null
        ? const Duration(seconds: 180)
        : Duration(milliseconds: (movetimeMs ?? 500) + 20000);
    try {
      return await completer.future.timeout(limit);
    } finally {
      _pending = null;
    }
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line == 'uciok') {
      if (_uciOk != null && !_uciOk!.isCompleted) _uciOk!.complete();
    } else if (line == 'readyok') {
      if (_readyOk != null && !_readyOk!.isCompleted) _readyOk!.complete();
    } else if (line.startsWith('info ')) {
      _parseInfo(line);
    } else if (line.startsWith('bestmove')) {
      final c = _pending;
      if (c != null && !c.isCompleted) {
        final keys = _lines.keys.toList()..sort();
        c.complete([for (final k in keys) _lines[k]!]);
      }
    }
  }

  void _parseInfo(String line) {
    final t = line.split(' ');
    int depth = 0;
    int multipv = 1;
    int? cp;
    int? mate;
    bool bound = false;
    List<String> pv = const [];
    for (int i = 0; i < t.length; i++) {
      final tok = t[i];
      if (tok == 'depth' && i + 1 < t.length) {
        depth = int.tryParse(t[i + 1]) ?? depth;
      } else if (tok == 'multipv' && i + 1 < t.length) {
        multipv = int.tryParse(t[i + 1]) ?? multipv;
      } else if (tok == 'score' && i + 2 < t.length) {
        if (t[i + 1] == 'cp') {
          cp = int.tryParse(t[i + 2]);
        } else if (t[i + 1] == 'mate') {
          mate = int.tryParse(t[i + 2]);
        }
      } else if (tok == 'lowerbound' || tok == 'upperbound') {
        bound = true;
      } else if (tok == 'pv') {
        pv = t.sublist(i + 1);
        break;
      }
    }
    if (bound || pv.isEmpty || (cp == null && mate == null)) return;
    int score;
    if (mate != null) {
      score = mate > 0 ? 10000 - mate : -10000 - mate;
    } else {
      score = cp!;
    }
    _lines[multipv] = EngineLine(
      multipv: multipv,
      score: score,
      mate: mate,
      pv: pv,
      depth: depth,
    );
  }
}
