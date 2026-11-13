import '../chess/chess.dart';

/// One principal variation reported by the engine, from the point of view of
/// the side to move in the analysed position.
class EngineLine {
  final int multipv; // 1 = best
  final int score; // centipawns, mates mapped to +/-10000 +/- distance
  final int? mate; // moves to mate (positive = side to move mates), if any
  final List<String> pv; // UCI moves
  final int depth;
  const EngineLine({
    required this.multipv,
    required this.score,
    required this.mate,
    required this.pv,
    required this.depth,
  });

  String get move => pv.isEmpty ? '' : pv.first;
}

abstract class EngineAnalyzer {
  /// Analyses [fen] and returns the top lines, best first.
  Future<List<EngineLine>> analyze(String fen,
      {int? movetimeMs, int? depth, int multiPv = 3});
}

enum PuzzleKind {
  missedMate,
  allowedMate,
  freePiece,
  fork,
  hangingPiece,
  ignoredThreat,
  bestMove,
}

enum PlayerFilter { both, white, black }

class Puzzle {
  final int id;
  final int ply; // index in the game's move list
  final int moveNumber;
  final int turn; // kWhite / kBlack — side to move (the player)
  final String fen;
  final String? lastMoveUci; // opponent's previous move, for context
  final String playedSan;
  final String playedUci;
  final String bestSan;
  final String bestUci;
  final List<String> solutionsUci; // every move accepted as correct
  final List<String> bestLineSan;
  final double winBefore; // win% for the player if best move is played
  final double winAfter; // win% after the move actually played
  final PuzzleKind kind;
  final String title;
  final String hint1;
  final String hint2;
  final String explanation;
  final String evalBefore;
  final String evalAfter;

  bool solved = false;
  bool revealed = false;

  Puzzle({
    required this.id,
    required this.ply,
    required this.moveNumber,
    required this.turn,
    required this.fen,
    required this.lastMoveUci,
    required this.playedSan,
    required this.playedUci,
    required this.bestSan,
    required this.bestUci,
    required this.solutionsUci,
    required this.bestLineSan,
    required this.winBefore,
    required this.winAfter,
    required this.kind,
    required this.title,
    required this.hint1,
    required this.hint2,
    required this.explanation,
    required this.evalBefore,
    required this.evalAfter,
  });

  double get drop => winBefore - winAfter;

  String get severity {
    if (drop >= 20) return 'Blunder';
    if (drop >= 10) return 'Mistake';
    return 'Inaccuracy';
  }

  String get sideName => turn == kWhite ? 'White' : 'Black';
}

class AnalysisResult {
  final ParsedGame game;
  final List<Puzzle> puzzles;
  final int pliesAnalysed;
  AnalysisResult(this.game, this.puzzles, this.pliesAnalysed);
}
