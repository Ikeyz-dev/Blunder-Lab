// Minimal, dependency-free chess rules: move generation, FEN, SAN, PGN.
// Squares are 0..63 with a1 = 0, b1 = 1, ... h1 = 7, a2 = 8, ... h8 = 63.

const int kEmpty = 0;
const int kPawn = 1;
const int kKnight = 2;
const int kBishop = 3;
const int kRook = 4;
const int kQueen = 5;
const int kKing = 6;

const int kWhite = 0;
const int kBlack = 8; // piece = type | colorBit

int pieceType(int p) => p & 7;
int pieceColor(int p) => p & 8;
int opposite(int color) => color == kWhite ? kBlack : kWhite;

const String kStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

String squareName(int sq) =>
    String.fromCharCode(97 + (sq & 7)) + (1 + (sq >> 3)).toString();

int squareFromName(String s) => (s.codeUnitAt(0) - 97) + 8 * (s.codeUnitAt(1) - 49);

class Move {
  final int from;
  final int to;
  final int promotion; // piece type or 0
  const Move(this.from, this.to, [this.promotion = 0]);

  String get uci {
    const promoChars = {kKnight: 'n', kBishop: 'b', kRook: 'r', kQueen: 'q'};
    return squareName(from) + squareName(to) + (promotion != 0 ? promoChars[promotion]! : '');
  }

  @override
  bool operator ==(Object other) =>
      other is Move && other.from == from && other.to == to && other.promotion == promotion;

  @override
  int get hashCode => from * 4096 + to * 8 + promotion;

  @override
  String toString() => uci;
}

class Position {
  final List<int> board; // 64 entries
  int turn; // kWhite or kBlack
  bool wK, wQ, bK, bQ; // castling rights
  int ep; // en passant target square or -1
  int halfmove;
  int fullmove;

  Position._(this.board, this.turn, this.wK, this.wQ, this.bK, this.bQ, this.ep,
      this.halfmove, this.fullmove);

  factory Position.initial() => Position.fromFen(kStartFen);

  Position copy() => Position._(List<int>.from(board), turn, wK, wQ, bK, bQ, ep, halfmove, fullmove);

  factory Position.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final board = List<int>.filled(64, 0);
    final rows = parts[0].split('/');
    if (rows.length != 8) throw FormatException('Bad FEN: $fen');
    for (int r = 0; r < 8; r++) {
      int file = 0;
      final rank = 7 - r;
      for (final ch in rows[r].split('')) {
        final d = int.tryParse(ch);
        if (d != null) {
          file += d;
        } else {
          final lower = ch.toLowerCase();
          const types = {'p': kPawn, 'n': kKnight, 'b': kBishop, 'r': kRook, 'q': kQueen, 'k': kKing};
          final t = types[lower];
          if (t == null) throw FormatException('Bad FEN piece: $ch');
          board[rank * 8 + file] = t | (ch == lower ? kBlack : kWhite);
          file++;
        }
      }
    }
    final turn = (parts.length > 1 && parts[1] == 'b') ? kBlack : kWhite;
    final castle = parts.length > 2 ? parts[2] : '-';
    final ep = (parts.length > 3 && parts[3] != '-') ? squareFromName(parts[3]) : -1;
    final half = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    final full = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    return Position._(board, turn, castle.contains('K'), castle.contains('Q'),
        castle.contains('k'), castle.contains('q'), ep, half, full);
  }

  String get fen {
    final sb = StringBuffer();
    for (int rank = 7; rank >= 0; rank--) {
      int empty = 0;
      for (int file = 0; file < 8; file++) {
        final p = board[rank * 8 + file];
        if (p == 0) {
          empty++;
        } else {
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
          sb.write(_pieceChar(p));
        }
      }
      if (empty > 0) sb.write(empty);
      if (rank > 0) sb.write('/');
    }
    sb.write(turn == kWhite ? ' w ' : ' b ');
    String c = '';
    if (wK) c += 'K';
    if (wQ) c += 'Q';
    if (bK) c += 'k';
    if (bQ) c += 'q';
    sb.write(c.isEmpty ? '-' : c);
    sb.write(' ');
    sb.write(ep == -1 ? '-' : squareName(ep));
    sb.write(' $halfmove $fullmove');
    return sb.toString();
  }

  static String _pieceChar(int p) {
    const chars = ['', 'p', 'n', 'b', 'r', 'q', 'k'];
    final c = chars[pieceType(p)];
    return pieceColor(p) == kWhite ? c.toUpperCase() : c;
  }

  int kingSquare(int color) {
    final target = kKing | color;
    for (int i = 0; i < 64; i++) {
      if (board[i] == target) return i;
    }
    return -1;
  }

  static const _knightD = [
    [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]
  ];
  static const _kingD = [
    [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]
  ];
  static const _bishopD = [[1, 1], [-1, 1], [-1, -1], [1, -1]];
  static const _rookD = [[1, 0], [0, 1], [-1, 0], [0, -1]];

  /// True if [sq] is attacked by any piece of [byColor].
  bool isAttacked(int sq, int byColor) {
    final f = sq & 7;
    final r = sq >> 3;
    // pawns
    final pr = byColor == kWhite ? r - 1 : r + 1;
    if (pr >= 0 && pr < 8) {
      for (final df in [-1, 1]) {
        final pf = f + df;
        if (pf >= 0 && pf < 8 && board[pr * 8 + pf] == (kPawn | byColor)) return true;
      }
    }
    for (final d in _knightD) {
      final nf = f + d[0], nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && board[nr * 8 + nf] == (kKnight | byColor)) {
        return true;
      }
    }
    for (final d in _kingD) {
      final nf = f + d[0], nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && board[nr * 8 + nf] == (kKing | byColor)) {
        return true;
      }
    }
    for (final d in _bishopD) {
      int nf = f + d[0], nr = r + d[1];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final p = board[nr * 8 + nf];
        if (p != 0) {
          if (pieceColor(p) == byColor && (pieceType(p) == kBishop || pieceType(p) == kQueen)) {
            return true;
          }
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
    for (final d in _rookD) {
      int nf = f + d[0], nr = r + d[1];
      while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        final p = board[nr * 8 + nf];
        if (p != 0) {
          if (pieceColor(p) == byColor && (pieceType(p) == kRook || pieceType(p) == kQueen)) {
            return true;
          }
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
    return false;
  }

  bool get inCheck {
    final k = kingSquare(turn);
    return k != -1 && isAttacked(k, opposite(turn));
  }

  List<Move> _pseudoMoves() {
    final moves = <Move>[];
    final us = turn;
    final them = opposite(us);
    for (int sq = 0; sq < 64; sq++) {
      final p = board[sq];
      if (p == 0 || pieceColor(p) != us) continue;
      final t = pieceType(p);
      final f = sq & 7;
      final r = sq >> 3;
      if (t == kPawn) {
        final dir = us == kWhite ? 1 : -1;
        final startRank = us == kWhite ? 1 : 6;
        final promoRank = us == kWhite ? 7 : 0;
        final nr = r + dir;
        if (nr < 0 || nr > 7) continue;
        void addPawn(int to) {
          if ((to >> 3) == promoRank) {
            for (final pt in [kQueen, kRook, kBishop, kKnight]) {
              moves.add(Move(sq, to, pt));
            }
          } else {
            moves.add(Move(sq, to));
          }
        }

        if (board[nr * 8 + f] == 0) {
          addPawn(nr * 8 + f);
          if (r == startRank && board[(r + 2 * dir) * 8 + f] == 0) {
            moves.add(Move(sq, (r + 2 * dir) * 8 + f));
          }
        }
        for (final df in [-1, 1]) {
          final nf = f + df;
          if (nf < 0 || nf > 7) continue;
          final to = nr * 8 + nf;
          final tp = board[to];
          if (tp != 0 && pieceColor(tp) == them) {
            addPawn(to);
          } else if (to == ep && tp == 0) {
            moves.add(Move(sq, to));
          }
        }
      } else if (t == kKnight || t == kKing) {
        final ds = t == kKnight ? _knightD : _kingD;
        for (final d in ds) {
          final nf = f + d[0], nr = r + d[1];
          if (nf < 0 || nf > 7 || nr < 0 || nr > 7) continue;
          final to = nr * 8 + nf;
          final tp = board[to];
          if (tp == 0 || pieceColor(tp) == them) moves.add(Move(sq, to));
        }
        if (t == kKing) {
          // castling
          if (us == kWhite && sq == 4) {
            if (wK && board[5] == 0 && board[6] == 0 && board[7] == (kRook | kWhite) &&
                !isAttacked(4, them) && !isAttacked(5, them) && !isAttacked(6, them)) {
              moves.add(const Move(4, 6));
            }
            if (wQ && board[3] == 0 && board[2] == 0 && board[1] == 0 &&
                board[0] == (kRook | kWhite) &&
                !isAttacked(4, them) && !isAttacked(3, them) && !isAttacked(2, them)) {
              moves.add(const Move(4, 2));
            }
          } else if (us == kBlack && sq == 60) {
            if (bK && board[61] == 0 && board[62] == 0 && board[63] == (kRook | kBlack) &&
                !isAttacked(60, them) && !isAttacked(61, them) && !isAttacked(62, them)) {
              moves.add(const Move(60, 62));
            }
            if (bQ && board[59] == 0 && board[58] == 0 && board[57] == 0 &&
                board[56] == (kRook | kBlack) &&
                !isAttacked(60, them) && !isAttacked(59, them) && !isAttacked(58, them)) {
              moves.add(const Move(60, 58));
            }
          }
        }
      } else {
        final ds = t == kBishop
            ? _bishopD
            : t == kRook
                ? _rookD
                : [..._bishopD, ..._rookD];
        for (final d in ds) {
          int nf = f + d[0], nr = r + d[1];
          while (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
            final to = nr * 8 + nf;
            final tp = board[to];
            if (tp == 0) {
              moves.add(Move(sq, to));
            } else {
              if (pieceColor(tp) == them) moves.add(Move(sq, to));
              break;
            }
            nf += d[0];
            nr += d[1];
          }
        }
      }
    }
    return moves;
  }

  List<Move> legalMoves() {
    final result = <Move>[];
    for (final m in _pseudoMoves()) {
      final next = copy()..applyMove(m);
      final k = next.kingSquare(turn);
      if (k != -1 && !next.isAttacked(k, opposite(turn))) result.add(m);
    }
    return result;
  }

  /// Applies [m] (assumed legal) in place.
  void applyMove(Move m) {
    final p = board[m.from];
    final t = pieceType(p);
    final captured = board[m.to];
    int newEp = -1;

    // en passant capture
    if (t == kPawn && m.to == ep && captured == 0 && (m.from & 7) != (m.to & 7)) {
      final capSq = turn == kWhite ? m.to - 8 : m.to + 8;
      board[capSq] = 0;
    }
    // castling rook move
    if (t == kKing && (m.to - m.from).abs() == 2) {
      if (m.to == 6) {
        board[5] = board[7];
        board[7] = 0;
      } else if (m.to == 2) {
        board[3] = board[0];
        board[0] = 0;
      } else if (m.to == 62) {
        board[61] = board[63];
        board[63] = 0;
      } else if (m.to == 58) {
        board[59] = board[56];
        board[56] = 0;
      }
    }
    // double pawn push sets ep square
    if (t == kPawn && (m.to - m.from).abs() == 16) {
      newEp = (m.from + m.to) ~/ 2;
    }

    board[m.to] = m.promotion != 0 ? (m.promotion | pieceColor(p)) : p;
    board[m.from] = 0;

    // castling rights
    if (t == kKing) {
      if (turn == kWhite) {
        wK = false;
        wQ = false;
      } else {
        bK = false;
        bQ = false;
      }
    }
    if (m.from == 0 || m.to == 0) wQ = false;
    if (m.from == 7 || m.to == 7) wK = false;
    if (m.from == 56 || m.to == 56) bQ = false;
    if (m.from == 63 || m.to == 63) bK = false;

    halfmove = (t == kPawn || captured != 0) ? 0 : halfmove + 1;
    if (turn == kBlack) fullmove++;
    turn = opposite(turn);
    ep = newEp;
  }

  bool get isCheckmate => inCheck && legalMoves().isEmpty;
  bool get isStalemate => !inCheck && legalMoves().isEmpty;
  bool get isGameOver => legalMoves().isEmpty;

  /// Finds the legal move matching a UCI string such as "e2e4" or "e7e8q".
  Move? parseUci(String uci) {
    if (uci.length < 4) return null;
    final from = squareFromName(uci.substring(0, 2));
    final to = squareFromName(uci.substring(2, 4));
    int promo = 0;
    if (uci.length > 4) {
      promo = const {'n': kKnight, 'b': kBishop, 'r': kRook, 'q': kQueen}[uci[4]] ?? 0;
    }
    for (final m in legalMoves()) {
      if (m.from == from && m.to == to && m.promotion == promo) return m;
    }
    return null;
  }

  bool isCapture(Move m) {
    if (board[m.to] != 0) return true;
    return pieceType(board[m.from]) == kPawn && m.to == ep && (m.from & 7) != (m.to & 7);
  }

  /// SAN for [m] in this position (including +/# suffix).
  String toSan(Move m, [List<Move>? legal]) {
    final p = board[m.from];
    final t = pieceType(p);
    final sb = StringBuffer();
    if (t == kKing && (m.to - m.from).abs() == 2) {
      sb.write(m.to > m.from ? 'O-O' : 'O-O-O');
    } else {
      final cap = isCapture(m);
      if (t == kPawn) {
        if (cap) sb.write(String.fromCharCode(97 + (m.from & 7)));
      } else {
        const letters = ['', '', 'N', 'B', 'R', 'Q', 'K'];
        sb.write(letters[t]);
        legal ??= legalMoves();
        bool others = false, sameFile = false, sameRank = false;
        for (final o in legal) {
          if (o == m || o.to != m.to || o.from == m.from) continue;
          if (pieceType(board[o.from]) != t) continue;
          others = true;
          if ((o.from & 7) == (m.from & 7)) sameFile = true;
          if ((o.from >> 3) == (m.from >> 3)) sameRank = true;
        }
        if (others) {
          if (!sameFile) {
            sb.write(String.fromCharCode(97 + (m.from & 7)));
          } else if (!sameRank) {
            sb.write((1 + (m.from >> 3)).toString());
          } else {
            sb.write(squareName(m.from));
          }
        }
      }
      if (cap) sb.write('x');
      sb.write(squareName(m.to));
      if (m.promotion != 0) {
        const letters = ['', '', 'N', 'B', 'R', 'Q', 'K'];
        sb.write('=${letters[m.promotion]}');
      }
    }
    final next = copy()..applyMove(m);
    if (next.inCheck) {
      sb.write(next.legalMoves().isEmpty ? '#' : '+');
    }
    return sb.toString();
  }

  /// Parses SAN (tolerant of check marks, annotations, 0-0 castling).
  Move? parseSan(String san) {
    var s = san.replaceAll(RegExp(r'[+#!?]+$'), '').replaceAll('0', 'O').trim();
    if (s.isEmpty) return null;
    final legal = legalMoves();
    final norm = s.replaceAll('=', '').replaceAll('x', '').replaceAll('-', '');
    for (final m in legal) {
      final cand = toSan(m, legal)
          .replaceAll(RegExp(r'[+#]'), '')
          .replaceAll('=', '')
          .replaceAll('x', '')
          .replaceAll('-', '');
      if (cand == norm) return m;
    }
    // Lenient: promotion without '=' already handled; try case-insensitive piece letter for e.g. "nf3"
    return null;
  }

  /// Squares holding enemy pieces that the piece on [sq] currently attacks
  /// (ignores pins; used for fork detection).
  List<int> attackedEnemySquares(int sq) {
    final p = board[sq];
    if (p == 0) return const [];
    final tmp = copy()
      ..turn = pieceColor(p)
      ..ep = -1;
    final out = <int>[];
    for (final m in tmp._pseudoMoves()) {
      if (m.from != sq) continue;
      final target = tmp.board[m.to];
      if (target != 0 && pieceColor(target) != pieceColor(p) && !out.contains(m.to)) {
        out.add(m.to);
      }
    }
    return out;
  }

  int perft(int depth) {
    if (depth == 0) return 1;
    final moves = legalMoves();
    if (depth == 1) return moves.length;
    int n = 0;
    for (final m in moves) {
      final next = copy()..applyMove(m);
      n += next.perft(depth - 1);
    }
    return n;
  }
}

// ---------------------------------------------------------------------------
// PGN
// ---------------------------------------------------------------------------

class ParsedGame {
  final Map<String, String> headers;
  final String startFen;
  final List<String> sans; // as played
  final List<Move> moves;
  final String? error; // set if parsing stopped early
  ParsedGame(this.headers, this.startFen, this.sans, this.moves, this.error);

  String get white => headers['White'] ?? 'White';
  String get black => headers['Black'] ?? 'Black';
  String get result => headers['Result'] ?? '*';
}

ParsedGame parsePgn(String text) {
  final headers = <String, String>{};
  final headerRe = RegExp(r'^\s*\[\s*(\w+)\s+"((?:[^"\\]|\\.)*)"\s*\]\s*$', multiLine: true);
  for (final m in headerRe.allMatches(text)) {
    headers[m.group(1)!] = m.group(2)!;
  }
  var body = text.replaceAll(headerRe, '');
  // Only keep the first game if several were pasted.
  final secondGame = RegExp(r'\n\s*\n\s*\[Event ').firstMatch(body);
  if (secondGame != null) body = body.substring(0, secondGame.start);

  // strip comments, variations, NAGs, clock annotations
  body = body.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
  body = body.replaceAll(RegExp(r';[^\n]*'), ' ');
  String stripNested(String s) {
    final out = StringBuffer();
    int depth = 0;
    for (final ch in s.split('')) {
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        out.write(ch);
      }
    }
    return out.toString();
  }

  body = stripNested(body);
  body = body.replaceAll(RegExp(r'\$\d+'), ' ');

  final startFen = headers['FEN'] ?? kStartFen;
  Position pos;
  try {
    pos = Position.fromFen(startFen);
  } catch (e) {
    return ParsedGame(headers, startFen, [], [], 'Invalid FEN in PGN header.');
  }

  final tokens = body.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  final sans = <String>[];
  final moves = <Move>[];
  String? error;
  for (var tok in tokens) {
    if (tok == '1-0' || tok == '0-1' || tok == '1/2-1/2' || tok == '*') break;
    tok = tok.replaceAll(RegExp(r'^\d+\.(\.\.)?'), '');
    tok = tok.replaceAll(RegExp(r'^\.\.\.'), '');
    if (tok.isEmpty) continue;
    final mv = pos.parseSan(tok);
    if (mv == null) {
      error = 'Could not read move "$tok" (move ${moves.length + 1}).';
      break;
    }
    sans.add(pos.toSan(mv));
    moves.add(mv);
    pos.applyMove(mv);
  }
  return ParsedGame(headers, startFen, sans, moves, error);
}
