import 'dart:math' as math;

import '../chess/chess.dart';
import 'models.dart';

/// Win probability (0..100) for the side the score is from, using the same
/// logistic curve Lichess uses.
double winPercent(int score) {
  if (score >= 9000) return 100;
  if (score <= -9000) return 0;
  final cp = score.clamp(-1000, 1000);
  return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1);
}

String formatScore(int score, {int? mate}) {
  if (mate != null) return mate > 0 ? '#$mate' : '#$mate';
  if (score >= 9000) return '#';
  if (score <= -9000) return '-#';
  final v = (score / 100).toStringAsFixed(1);
  return score > 0 ? '+$v' : v;
}

int _pieceValue(int type) {
  switch (type) {
    case kPawn:
      return 1;
    case kKnight:
    case kBishop:
      return 3;
    case kRook:
      return 5;
    case kQueen:
      return 9;
    default:
      return 0; // king
  }
}

String _pieceName(int type) {
  switch (type) {
    case kPawn:
      return 'pawn';
    case kKnight:
      return 'knight';
    case kBishop:
      return 'bishop';
    case kRook:
      return 'rook';
    case kQueen:
      return 'queen';
    default:
      return 'king';
  }
}

class _Eval {
  final List<EngineLine> lines;
  final int score; // side-to-move point of view
  final int? mate;
  _Eval(this.lines, this.score, this.mate);
  EngineLine? get best => lines.isEmpty ? null : lines.first;
}

Future<AnalysisResult> analyzeGame(
  ParsedGame game,
  EngineAnalyzer engine, {
  int? movetimeMs,
  int? depth,
  PlayerFilter filter = PlayerFilter.both,
  double minDrop = 8,
  int maxPuzzles = 25,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  // Positions before each move, plus the final position.
  final positions = <Position>[Position.fromFen(game.startFen)];
  for (final m in game.moves) {
    final next = positions.last.copy()..applyMove(m);
    positions.add(next);
  }
  final total = positions.length;
  final evals = <_Eval>[];

  for (int i = 0; i < total; i++) {
    if (isCancelled != null && isCancelled()) {
      return AnalysisResult(game, [], i);
    }
    final pos = positions[i];
    if (pos.legalMoves().isEmpty) {
      evals.add(_Eval(const [], pos.inCheck ? -10000 : 0, pos.inCheck ? 0 : null));
    } else {
      final lines = await engine.analyze(pos.fen,
          movetimeMs: movetimeMs, depth: depth, multiPv: 3);
      if (lines.isEmpty) {
        evals.add(_Eval(const [], 0, null));
      } else {
        evals.add(_Eval(lines, lines.first.score, lines.first.mate));
      }
    }
    onProgress?.call(i + 1, total);
  }

  final candidates = <Puzzle>[];
  for (int i = 0; i < game.moves.length; i++) {
    final pos = positions[i];
    if (filter == PlayerFilter.white && pos.turn != kWhite) continue;
    if (filter == PlayerFilter.black && pos.turn != kBlack) continue;
    final ev = evals[i];
    final best = ev.best;
    if (best == null) continue;
    final played = game.moves[i];
    if (best.move == played.uci) continue;

    // Score of the move actually played, from the mover's point of view.
    int playedScore;
    int? playedMate;
    final match = ev.lines.where((l) => l.move == played.uci);
    if (match.isNotEmpty) {
      playedScore = match.first.score;
      playedMate = match.first.mate;
    } else {
      final after = evals[i + 1];
      playedScore = -after.score;
      playedMate = after.mate == null ? null : -after.mate!;
    }

    final wpBest = winPercent(best.score);
    final wpPlayed = winPercent(playedScore);
    final drop = wpBest - wpPlayed;
    if (drop < minDrop) continue;
    if (wpBest < 12) continue; // hopeless position: not a fair puzzle

    // Accepted solutions: any top line almost as good as the best one.
    final solutions = <String>[];
    for (final l in ev.lines) {
      if (l.move == played.uci) continue;
      if (wpBest - winPercent(l.score) <= 4) solutions.add(l.move);
    }
    if (solutions.isEmpty) solutions.add(best.move);

    final bestMove = pos.parseUci(best.move);
    if (bestMove == null) continue;

    final puzzle = _buildPuzzle(
      id: candidates.length,
      ply: i,
      pos: pos,
      played: played,
      bestMove: bestMove,
      bestLine: best,
      replyLine: evals[i + 1].best,
      prevMove: i > 0 ? game.moves[i - 1] : null,
      solutions: solutions,
      wpBest: wpBest,
      wpPlayed: wpPlayed,
      playedScore: playedScore,
      playedMate: playedMate,
    );
    if (puzzle != null) candidates.add(puzzle);
  }

  var chosen = candidates;
  if (chosen.length > maxPuzzles) {
    chosen = [...chosen]..sort((a, b) => b.drop.compareTo(a.drop));
    chosen = chosen.sublist(0, maxPuzzles);
    chosen.sort((a, b) => a.ply.compareTo(b.ply));
  }
  // Re-number in game order.
  final numbered = <Puzzle>[];
  for (int k = 0; k < chosen.length; k++) {
    final p = chosen[k];
    numbered.add(Puzzle(
      id: k,
      ply: p.ply,
      moveNumber: p.moveNumber,
      turn: p.turn,
      fen: p.fen,
      lastMoveUci: p.lastMoveUci,
      playedSan: p.playedSan,
      playedUci: p.playedUci,
      bestSan: p.bestSan,
      bestUci: p.bestUci,
      solutionsUci: p.solutionsUci,
      bestLineSan: p.bestLineSan,
      winBefore: p.winBefore,
      winAfter: p.winAfter,
      kind: p.kind,
      title: p.title,
      hint1: p.hint1,
      hint2: p.hint2,
      explanation: p.explanation,
      evalBefore: p.evalBefore,
      evalAfter: p.evalAfter,
    ));
  }
  return AnalysisResult(game, numbered, total);
}

List<String> _pvToSan(Position start, List<String> pv, {int maxMoves = 6}) {
  final pos = start.copy();
  final out = <String>[];
  for (final u in pv.take(maxMoves)) {
    final m = pos.parseUci(u);
    if (m == null) break;
    out.add(pos.toSan(m));
    pos.applyMove(m);
  }
  return out;
}

Puzzle? _buildPuzzle({
  required int id,
  required int ply,
  required Position pos,
  required Move played,
  required Move bestMove,
  required EngineLine bestLine,
  required EngineLine? replyLine,
  required Move? prevMove,
  required List<String> solutions,
  required double wpBest,
  required double wpPlayed,
  required int playedScore,
  required int? playedMate,
}) {
  final us = pos.turn;
  final them = opposite(us);
  final playedSan = pos.toSan(played);
  final bestSan = pos.toSan(bestMove);
  final afterPlayed = pos.copy()..applyMove(played);
  final afterBest = pos.copy()..applyMove(bestMove);
  final bestPiece = pieceType(pos.board[bestMove.from]);
  final fromName = squareName(bestMove.from);
  final line = _pvToSan(pos, bestLine.pv);

  // Opponent's best reply to the move that was actually played.
  Move? reply;
  if (replyLine != null && replyLine.move.isNotEmpty) {
    reply = afterPlayed.parseUci(replyLine.move);
  }

  PuzzleKind kind = PuzzleKind.bestMove;
  String title = 'Find the better move';
  String hint1 = 'Look at the checks, captures and threats for both sides.';
  String explanation = '$bestSan was stronger than $playedSan.';

  // 1. Missed forced mate.
  if (bestLine.mate != null && bestLine.mate! > 0 && bestLine.mate! <= 6 &&
      !(playedMate != null && playedMate > 0)) {
    kind = PuzzleKind.missedMate;
    title = 'Missed checkmate in ${bestLine.mate}';
    hint1 = 'There is a forced checkmate here. Check every check.';
    explanation =
        '$bestSan starts a forced checkmate in ${bestLine.mate}. '
        '$playedSan let the win slip away.';
  } else {
    // 2. Free material for the player.
    final capturedBest = afterBest.board[bestMove.to];
    final bestWasCapture = pos.isCapture(bestMove);
    int capturedValue = 0;
    int capturedType = 0;
    if (bestWasCapture) {
      capturedType = capturedBest != 0 ? pieceType(capturedBest) : kPawn;
      capturedValue = _pieceValue(capturedType);
    }
    bool recapture = false;
    if (bestWasCapture) {
      for (final m in afterBest.legalMoves()) {
        if (m.to == bestMove.to && afterBest.isCapture(m)) {
          recapture = true;
          break;
        }
      }
    }
    final gain = capturedValue - (recapture ? _pieceValue(bestPiece) : 0);

    // 3. Fork created by the best move.
    final forked = <int>[];
    if (bestPiece != kKing) {
      for (final t in afterBest.attackedEnemySquares(bestMove.to)) {
        final tv = pieceType(afterBest.board[t]);
        final defended = afterBest.isAttacked(t, them);
        if (tv == kKing ||
            _pieceValue(tv) > _pieceValue(bestPiece) ||
            (!defended && tv != kPawn)) {
          forked.add(t);
        }
      }
    }

    // 4. What did the played move allow?
    bool replyWins = false;
    int replyCapturedType = 0;
    if (reply != null && afterPlayed.isCapture(reply)) {
      final cp = afterPlayed.board[reply.to];
      replyCapturedType = cp != 0 ? pieceType(cp) : kPawn;
      final afterReply = afterPlayed.copy()..applyMove(reply);
      bool recapturable = false;
      for (final m in afterReply.legalMoves()) {
        if (m.to == reply.to && afterReply.isCapture(m)) {
          recapturable = true;
          break;
        }
      }
      final attackerValue = _pieceValue(pieceType(afterPlayed.board[reply.from]));
      // Material the played move itself took does not count as lost.
      int playedGain = 0;
      if (pos.isCapture(played)) {
        final pc = pos.board[played.to];
        playedGain = _pieceValue(pc != 0 ? pieceType(pc) : kPawn);
      }
      final net = _pieceValue(replyCapturedType) -
          (recapturable ? attackerValue : 0) -
          playedGain;
      replyWins = net >= 2;
    }

    // Did the played move allow a forced mate against the player?
    final allowedMate = replyLine != null &&
        replyLine.mate != null &&
        replyLine.mate! > 0 &&
        replyLine.mate! <= 3;

    if (bestWasCapture && gain >= 2) {
      kind = PuzzleKind.freePiece;
      final name = _pieceName(capturedType);
      title = 'Free material was available';
      hint1 = 'One of your opponent\'s pieces can be won. Look for a capture.';
      explanation = recapture
          ? '$bestSan wins a $name for a smaller piece.'
          : '$bestSan wins a $name that was not protected.';
    } else if (forked.length >= 2) {
      kind = PuzzleKind.fork;
      final names = forked.map((s) => _pieceName(pieceType(afterBest.board[s]))).toList();
      title = 'There was a fork';
      hint1 = 'Look for a move that attacks two pieces at once.';
      explanation =
          '$bestSan forks the ${names[0]} and the ${names[1]}, so something has to fall.';
    } else if (allowedMate && reply != null) {
      kind = PuzzleKind.allowedMate;
      title = 'Checkmate was coming';
      hint1 = 'Your opponent has a forced mate if you do nothing. Defend!';
      explanation = '$playedSan allowed ${afterPlayed.toSan(reply)} and a forced '
          'checkmate in ${replyLine.mate}. $bestSan kept you safe.';
    } else if (replyWins && reply != null) {
      // Was that capture already on the board before the move was played?
      bool threatExisted = false;
      if (!pos.inCheck) {
        final nm = pos.copy()
          ..turn = them
          ..ep = -1;
        for (final m in nm.legalMoves()) {
          if (m.from == reply.from && m.to == reply.to) {
            threatExisted = true;
            break;
          }
        }
      }
      final lost = _pieceName(replyCapturedType);
      final replySan = afterPlayed.toSan(reply);
      if (reply.to == played.to) {
        kind = PuzzleKind.hangingPiece;
        title = 'A piece was left hanging';
        hint1 = 'Check whether the piece you moved can be captured.';
        explanation = '$playedSan put your piece where it could be taken: '
            'the reply $replySan wins a $lost.';
      } else if (threatExisted) {
        kind = PuzzleKind.ignoredThreat;
        title = 'A threat was ignored';
        hint1 = 'Your opponent is threatening something. What is it?';
        explanation = 'Your opponent was threatening $replySan, and $playedSan '
            'did nothing about it, so you lose a $lost. $bestSan was better.';
      } else {
        kind = PuzzleKind.hangingPiece;
        title = 'A piece was left hanging';
        hint1 = 'Check what your move stopped protecting.';
        explanation = '$playedSan left a piece unprotected: '
            '$replySan wins a $lost.';
      }
    }
  }

  final pieceWord = _pieceName(bestPiece);
  final hint2 = 'Move the $pieceWord on $fromName.';
  final expl = StringBuffer(explanation);
  if (line.length > 1) {
    expl.write('\n\nBest line: ${line.join(' ')}');
  }

  final lastMoveUci = prevMove?.uci;
  return Puzzle(
    id: id,
    ply: ply,
    moveNumber: pos.fullmove,
    turn: us,
    fen: pos.fen,
    lastMoveUci: lastMoveUci,
    playedSan: playedSan,
    playedUci: played.uci,
    bestSan: bestSan,
    bestUci: bestMove.uci,
    solutionsUci: solutions,
    bestLineSan: line,
    winBefore: wpBest,
    winAfter: wpPlayed,
    kind: kind,
    title: title,
    hint1: hint1,
    hint2: hint2,
    explanation: expl.toString(),
    evalBefore: formatScore(bestLine.score, mate: bestLine.mate),
    evalAfter: formatScore(playedScore, mate: playedMate),
  );
}
