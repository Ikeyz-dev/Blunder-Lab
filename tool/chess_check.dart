import '../lib/chess/chess.dart';

void check(String name, int got, int want) {
  print('${got == want ? "OK  " : "FAIL"} $name: got $got want $want');
  if (got != want) throw Exception('perft mismatch');
}

void main() {
  check('startpos d3', Position.initial().perft(3), 8902);
  check('startpos d4', Position.initial().perft(4), 197281);
  final kiwipete = Position.fromFen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
  check('kiwipete d3', kiwipete.perft(3), 97862);
  final pos3 = Position.fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
  check('pos3 d4', pos3.perft(4), 43238);
  final pos4 = Position.fromFen('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1');
  check('pos4 d3', pos4.perft(3), 9467);
  final pos5 = Position.fromFen('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8');
  check('pos5 d3', pos5.perft(3), 62379);

  // PGN: Opera game
  const pgn = '''
[Event "Opera"]
[White "Paul Morphy"]
[Black "Duke Karl / Count Isouard"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 {a comment} 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7
8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6
15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
''';
  final g = parsePgn(pgn);
  print('Parsed ${g.moves.length} plies, error=${g.error}, white=${g.white}');
  final p = Position.fromFen(g.startFen);
  for (final m in g.moves) { p.applyMove(m); }
  print('final FEN ${p.fen} mate=${p.isCheckmate}');
  print('last SAN ${g.sans.last}');
  if (g.moves.length != 33 || !p.isCheckmate) throw Exception('PGN test failed');
  print('SAN sample: ${g.sans.take(8).join(' ')}');
  // SAN disambiguation + promotion + castling
  final t = Position.fromFen('r3k3/1P6/8/8/8/8/8/R3K2R w KQq - 0 1');
  print(t.legalMoves().map((m) => t.toSan(m)).join(' '));
}
