// Runs the whole puzzle pipeline with a tiny stand-in engine (material +
// 3-ply alpha-beta). Real Stockfish is used inside the app; this only proves
// the plumbing (scoring, classification, hints) works.
import '../lib/analysis/analyzer.dart';
import '../lib/analysis/models.dart';
import '../lib/chess/chess.dart';

const _vals = [0, 100, 320, 330, 500, 900, 0];

int _material(Position p) {
  int s = 0;
  for (final pc in p.board) {
    if (pc == 0) continue;
    final v = _vals[pieceType(pc)];
    s += pieceColor(pc) == p.turn ? v : -v;
  }
  return s;
}

int _search(Position p, int depth, int alpha, int beta, int ply) {
  final moves = p.legalMoves();
  if (moves.isEmpty) return p.inCheck ? -10000 + ply : 0;
  if (depth == 0) return _material(p);
  // captures first
  moves.sort((a, b) => (p.isCapture(b) ? 1 : 0) - (p.isCapture(a) ? 1 : 0));
  for (final m in moves) {
    final n = p.copy()..applyMove(m);
    final v = -_search(n, depth - 1, -beta, -alpha, ply + 1);
    if (v >= beta) return beta;
    if (v > alpha) alpha = v;
  }
  return alpha;
}

class FakeEngine implements EngineAnalyzer {
  @override
  Future<List<EngineLine>> analyze(String fen, {int? movetimeMs, int? depth, int multiPv = 3}) async {
    final p = Position.fromFen(fen);
    final scored = <MapEntry<Move, int>>[];
    for (final m in p.legalMoves()) {
      final n = p.copy()..applyMove(m);
      scored.add(MapEntry(m, -_search(n, 2, -100000, 100000, 1)));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final out = <EngineLine>[];
    for (int i = 0; i < scored.length && i < multiPv; i++) {
      final sc = scored[i].value;
      int? mate;
      int score = sc;
      if (sc >= 9000) {
        mate = ((10000 - sc) + 1) ~/ 2;
        score = 10000 - mate;
      } else if (sc <= -9000) {
        mate = -(((10000 + sc) + 1) ~/ 2);
        score = -10000 - mate;
      }
      out.add(EngineLine(multipv: i + 1, score: score, mate: mate, pv: [scored[i].key.uci], depth: 3));
    }
    return out;
  }
}

Future<void> run(String name, String pgn, PlayerFilter f) async {
  final g = parsePgn(pgn);
  print('== $name: ${g.moves.length} plies, err=${g.error}');
  final r = await analyzeGame(g, FakeEngine(), depth: 3, filter: f, minDrop: 15);
  for (final p in r.puzzles) {
    print('  #${p.id} move ${p.moveNumber} ${p.sideName} [${p.severity}] ${p.kind.name}: ${p.title}');
    print('     played ${p.playedSan} (${p.evalAfter}) best ${p.bestSan} (${p.evalBefore}) solutions=${p.solutionsUci}');
    print('     hint1: ${p.hint1} | hint2: ${p.hint2}');
    print('     ${p.explanation.replaceAll('\n', ' / ')}');
  }
  if (r.puzzles.isEmpty) print('  (no puzzles)');
}

Future<void> main() async {
  await run('scholars', '1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0', PlayerFilter.both);
  await run('opera', '''
[White "Paul Morphy"]
[Black "Duke Karl / Count Isouard"]
1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7
8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6
15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0''', PlayerFilter.both);
  await run('fork+hang', '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6 4. O-O Nxe4 5. Re1 Nd6 6. Nxe5 Be7 7. Bf1 O-O 8. Nxc6 dxc6 9. Qe2 Re8 10. Qxe8+ Bf8 11. Qxd8 1-0', PlayerFilter.both);
}
