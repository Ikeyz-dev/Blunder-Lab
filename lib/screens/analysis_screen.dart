import 'package:flutter/material.dart';

import '../analysis/analyzer.dart';
import '../analysis/models.dart';
import '../chess/chess.dart';
import '../engine/stockfish_engine.dart';
import '../theme.dart';
import '../widgets/chess_board.dart';
import 'puzzle_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.game,
    required this.filter,
    required this.depth,
    required this.minDrop,
  });

  final ParsedGame game;
  final PlayerFilter filter;
  final int depth;
  final double minDrop;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String _status = 'Starting the chess engine...';
  String? _error;
  AnalysisResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    StockfishEngine.instanceOrNull?.stop();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _result = null;
      _done = 0;
      _total = widget.game.moves.length + 1;
      _status = 'Starting the chess engine...';
    });
    try {
      final engine = await StockfishEngine.shared();
      if (_cancelled) return;
      await engine.newGame();
      if (_cancelled) return;
      if (mounted) setState(() => _status = 'Checking every position...');
      final result = await analyzeGame(
        widget.game,
        engine,
        depth: widget.depth,
        filter: widget.filter,
        minDrop: widget.minDrop,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted || _cancelled) return;
      setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(result == null ? 'Analysing' : 'Your puzzles')),
      body: SafeArea(
        child: _error != null
            ? _buildError()
            : result == null
                ? _buildProgress()
                : _buildList(result),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.orange),
            const SizedBox(height: 12),
            const Text('Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _run, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final value = _total == 0 || _done == 0 ? null : _done / _total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.game.white} vs ${widget.game.black}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: value, minHeight: 10),
            ),
            const SizedBox(height: 16),
            Text(
              _done == 0 ? _status : 'Position $_done of $_total',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AnalysisResult result) {
    final puzzles = result.puzzles;
    final solved = puzzles.where((p) => p.solved).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${result.game.white} vs ${result.game.black}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${result.game.moves.length} moves · result ${result.game.result}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Text(
                puzzles.isEmpty
                    ? 'No clear mistakes found.'
                    : '${puzzles.length} puzzles found · $solved solved',
                style: const TextStyle(
                    color: AppColors.green, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (puzzles.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Nothing here dropped enough to count as a mistake for the side you picked. '
              'Try "Both sides" or a deeper analysis.',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
        for (int i = 0; i < puzzles.length; i++) _puzzleTile(puzzles, i),
      ],
    );
  }

  Color _severityColor(Puzzle p) {
    switch (p.severity) {
      case 'Blunder':
        return AppColors.red;
      case 'Mistake':
        return AppColors.orange;
      default:
        return AppColors.yellow;
    }
  }

  Widget _puzzleTile(List<Puzzle> puzzles, int i) {
    final p = puzzles[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => PuzzleScreen(puzzles: puzzles, index: i),
          ));
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: cardDecoration(),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ChessBoard(
                    position: Position.fromFen(p.fen),
                    flipped: p.turn == kBlack,
                    showCoordinates: false,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Puzzle ${i + 1}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Move ${p.moveNumber} · ${p.sideName} to play',
                        style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _severityColor(p).withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(p.severity,
                          style: TextStyle(
                              color: _severityColor(p),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              if (p.solved)
                const Icon(Icons.check_circle, color: AppColors.green)
              else if (p.revealed)
                const Icon(Icons.visibility, color: AppColors.muted)
              else
                const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
