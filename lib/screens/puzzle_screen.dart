import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../analysis/models.dart';
import '../chess/chess.dart';
import '../theme.dart';
import '../widgets/chess_board.dart';

enum _Status { playing, solved, revealed }

class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({super.key, required this.puzzles, required this.index});

  final List<Puzzle> puzzles;
  final int index;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  late final Puzzle puzzle = widget.puzzles[widget.index];
  late Position pos = Position.fromFen(puzzle.fen);
  Move? lastMove;
  int? selected;
  Set<int> targets = <int>{};
  int hintLevel = 0;
  int attempts = 0;
  _Status status = _Status.playing;
  String? message;
  Color messageColor = AppColors.muted;
  int? hintSquare;
  int? wrongSquare;
  String? doneHeadline;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final u = puzzle.lastMoveUci;
    if (u != null && u.length >= 4) {
      lastMove = Move(squareFromName(u.substring(0, 2)), squareFromName(u.substring(2, 4)));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<int?> _askPromotion() {
    final color = pos.turn;
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final t in [kQueen, kRook, kBishop, kKnight])
                InkWell(
                  onTap: () => Navigator.pop(ctx, t),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: SvgPicture.asset(pieceAsset(color | t)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSquareTap(int sq) {
    if (status != _Status.playing) return;
    final piece = pos.board[sq];
    if (selected != null && targets.contains(sq)) {
      _tryMove(selected!, sq);
      return;
    }
    if (piece != 0 && pieceColor(piece) == pos.turn) {
      setState(() {
        selected = sq;
        targets = {
          for (final m in pos.legalMoves())
            if (m.from == sq) m.to
        };
      });
      return;
    }
    setState(() {
      selected = null;
      targets = <int>{};
    });
  }

  Future<void> _tryMove(int from, int to) async {
    final candidates =
        pos.legalMoves().where((m) => m.from == from && m.to == to).toList();
    if (candidates.isEmpty) return;
    Move move = candidates.first;
    if (candidates.length > 1) {
      final promo = await _askPromotion();
      if (!mounted) return;
      if (promo == null) return;
      move = candidates.firstWhere((m) => m.promotion == promo,
          orElse: () => candidates.first);
    }

    attempts++;
    if (puzzle.solutionsUci.contains(move.uci)) {
      final san = pos.toSan(move);
      final isTop = move.uci == puzzle.bestUci;
      _finish(
        move,
        solved: true,
        headline: isTop
            ? 'Correct! $san'
            : 'Correct! $san works. The engine\'s top choice was ${puzzle.bestSan}.',
      );
    } else {
      final samAsGame = move.uci == puzzle.playedUci;
      _timer?.cancel();
      setState(() {
        wrongSquare = to;
        selected = null;
        targets = <int>{};
        message = samAsGame
            ? 'That is the move you played in the game. Look for something better.'
            : 'Not the best move. Try again, or use a hint.';
        messageColor = const Color(0xFFFF8A80);
      });
      _timer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => wrongSquare = null);
      });
    }
  }

  void _finish(Move move, {required bool solved, required String headline}) {
    _timer?.cancel();
    final next = pos.copy()..applyMove(move);
    setState(() {
      pos = next;
      lastMove = move;
      selected = null;
      targets = <int>{};
      wrongSquare = null;
      hintSquare = null;
      status = solved ? _Status.solved : _Status.revealed;
      doneHeadline = headline;
      message = null;
      if (solved) {
        puzzle.solved = true;
      } else {
        puzzle.revealed = true;
      }
    });
  }

  void _hint() {
    if (status != _Status.playing || hintLevel >= 2) return;
    setState(() {
      hintLevel++;
      if (hintLevel == 1) {
        message = puzzle.hint1;
      } else {
        message = puzzle.hint2;
        hintSquare = squareFromName(puzzle.bestUci.substring(0, 2));
      }
      messageColor = AppColors.blue;
    });
  }

  void _showSolution() {
    if (status != _Status.playing) return;
    final move = pos.parseUci(puzzle.bestUci);
    if (move == null) return;
    _finish(move, solved: false, headline: 'Solution: ${puzzle.bestSan}');
  }

  void _next() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PuzzleScreen(puzzles: widget.puzzles, index: widget.index + 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final whiteToMove = puzzle.turn == kWhite;
    final hasNext = widget.index + 1 < widget.puzzles.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Puzzle ${widget.index + 1} of ${widget.puzzles.length}'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: whiteToMove ? Colors.white : Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${puzzle.sideName} to move · find the better move',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              ChessBoard(
                position: pos,
                flipped: puzzle.turn == kBlack,
                selected: selected,
                targets: targets,
                lastMove: lastMove,
                hintSquare: hintSquare,
                wrongSquare: wrongSquare,
                onSquareTap: _onSquareTap,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: status == _Status.playing
                    ? _playingPanel()
                    : _donePanel(hasNext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playingPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration(
            border: message == null ? null : messageColor,
          ),
          child: Text(
            message ??
                'In your game you played ${puzzle.playedSan} here. Tap a piece, then a square.',
            style: TextStyle(
              fontSize: 15,
              color: message == null ? AppColors.muted : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hintLevel >= 2 ? null : _hint,
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(hintLevel == 0
                    ? 'Hint'
                    : hintLevel == 1
                        ? 'Another hint'
                        : 'Hints used'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showSolution,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Solution'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _donePanel(bool hasNext) {
    final solved = status == _Status.solved;
    final color = solved ? AppColors.green : AppColors.blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(border: color),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doneHeadline ?? '',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(height: 4),
              Text(puzzle.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(puzzle.explanation,
                  style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 12),
              Text(
                'In the game: ${puzzle.playedSan} (${puzzle.evalAfter})  ·  '
                'Best: ${puzzle.bestSan} (${puzzle.evalBefore})',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('All puzzles'),
              ),
            ),
            if (hasNext) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _next,
                  child: const Text('Next puzzle'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
