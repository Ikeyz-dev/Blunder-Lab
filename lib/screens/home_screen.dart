import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/models.dart';
import '../chess/chess.dart';
import '../sample.dart';
import '../theme.dart';
import 'analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ctrl = TextEditingController();
  PlayerFilter _filter = PlayerFilter.both;
  int _speed = 1; // 0 fast, 1 quick, 2 deep
  int _sens = 1; // 0 big mistakes only, 1 balanced, 2 everything
  String? _error;

  static const List<int> _depths = [11, 14, 18];
  static const List<String> _speedLabels = ['Fast (11)', 'Quick (14)', 'Deep (18)'];
  static const List<double> _drops = [15, 8, 5];
  static const List<String> _sensLabels = ['Big mistakes', 'Balanced', 'Every slip'];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _error = 'Your clipboard is empty. Copy a PGN first.');
      return;
    }
    setState(() {
      _ctrl.text = text;
      _error = null;
    });
  }

  void _start() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste a PGN first.');
      return;
    }
    final game = parsePgn(text);
    if (game.moves.length < 4) {
      setState(() => _error =
          game.error ?? 'I could not find enough moves in that PGN.');
      return;
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    if (game.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${game.error} Analysing the first ${game.moves.length} moves.'),
      ));
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => AnalysisScreen(
        game: game,
        filter: _filter,
        depth: _depths[_speed],
        minDrop: _drops[_sens],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.extension, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Blunder Lab',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste a game. I will find the moments you missed and turn them into puzzles.',
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                minLines: 7,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '[Event "Casual game"]\n\n1. e4 e5 2. Nf3 Nc6 ...',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Paste'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _ctrl.text = kSamplePgn;
                      _error = null;
                    }),
                    child: const Text('Sample game'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _ctrl.clear();
                      _error = null;
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Puzzles from', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Both sides'),
                    selected: _filter == PlayerFilter.both,
                    onSelected: (_) => setState(() => _filter = PlayerFilter.both),
                  ),
                  ChoiceChip(
                    label: const Text('White'),
                    selected: _filter == PlayerFilter.white,
                    onSelected: (_) => setState(() => _filter = PlayerFilter.white),
                  ),
                  ChoiceChip(
                    label: const Text('Black'),
                    selected: _filter == PlayerFilter.black,
                    onSelected: (_) => setState(() => _filter = PlayerFilter.black),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('How many puzzles', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (int i = 0; i < _sensLabels.length; i++)
                    ChoiceChip(
                      label: Text(_sensLabels[i]),
                      selected: _sens == i,
                      onSelected: (_) => setState(() => _sens = i),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Analysis depth', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (int i = 0; i < _speedLabels.length; i++)
                    ChoiceChip(
                      label: Text(_speedLabels[i]),
                      selected: _speed == i,
                      onSelected: (_) => setState(() => _speed = i),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Find my mistakes',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
