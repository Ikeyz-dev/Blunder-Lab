import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../chess/chess.dart';

/// Chess.com "green" board colours.
class BoardColors {
  static const light = Color(0xFFEEEED2);
  static const dark = Color(0xFF769656);
  static const lightHighlight = Color(0xFFF6F669);
  static const darkHighlight = Color(0xFFBACA2B);
}

String pieceAsset(int piece) {
  const letters = ['', 'P', 'N', 'B', 'R', 'Q', 'K'];
  final c = pieceColor(piece) == kWhite ? 'w' : 'b';
  return 'assets/pieces/$c${letters[pieceType(piece)]}.svg';
}

class ChessBoard extends StatelessWidget {
  const ChessBoard({
    super.key,
    required this.position,
    this.flipped = false,
    this.selected,
    this.targets = const <int>{},
    this.lastMove,
    this.hintSquare,
    this.wrongSquare,
    this.onSquareTap,
    this.showCoordinates = true,
  });

  final Position position;
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final Move? lastMove;
  final int? hintSquare;
  final int? wrongSquare;
  final void Function(int square)? onSquareTap;
  final bool showCoordinates;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final sq = size / 8;
          final checkSquare = position.inCheck ? position.kingSquare(position.turn) : null;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onSquareTap == null
                ? null
                : (details) {
                    final col = (details.localPosition.dx / sq).floor().clamp(0, 7);
                    final row = (details.localPosition.dy / sq).floor().clamp(0, 7);
                    final file = flipped ? 7 - col : col;
                    final rank = flipped ? row : 7 - row;
                    onSquareTap!(rank * 8 + file);
                  },
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(size, size),
                    painter: _BoardPainter(
                      flipped: flipped,
                      selected: selected,
                      targets: targets,
                      position: position,
                      lastMove: lastMove,
                      hintSquare: hintSquare,
                      wrongSquare: wrongSquare,
                      checkSquare: checkSquare,
                      showCoordinates: showCoordinates,
                    ),
                  ),
                  for (int s = 0; s < 64; s++)
                    if (position.board[s] != 0)
                      Positioned(
                        left: (flipped ? 7 - (s & 7) : (s & 7)) * sq,
                        top: (flipped ? (s >> 3) : 7 - (s >> 3)) * sq,
                        width: sq,
                        height: sq,
                        child: IgnorePointer(
                          child: SvgPicture.asset(pieceAsset(position.board[s])),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.flipped,
    required this.selected,
    required this.targets,
    required this.position,
    required this.lastMove,
    required this.hintSquare,
    required this.wrongSquare,
    required this.checkSquare,
    required this.showCoordinates,
  });

  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final Position position;
  final Move? lastMove;
  final int? hintSquare;
  final int? wrongSquare;
  final int? checkSquare;
  final bool showCoordinates;

  Rect _rect(int s, double sq) {
    final col = flipped ? 7 - (s & 7) : (s & 7);
    final row = flipped ? (s >> 3) : 7 - (s >> 3);
    return Rect.fromLTWH(col * sq, row * sq, sq, sq);
  }

  bool _isLight(int s) => (((s & 7) + (s >> 3)) % 2) == 1;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    final paint = Paint();

    for (int s = 0; s < 64; s++) {
      final light = _isLight(s);
      final highlighted = s == selected ||
          (lastMove != null && (s == lastMove!.from || s == lastMove!.to));
      paint.color = highlighted
          ? (light ? BoardColors.lightHighlight : BoardColors.darkHighlight)
          : (light ? BoardColors.light : BoardColors.dark);
      canvas.drawRect(_rect(s, sq), paint);
    }

    if (hintSquare != null) {
      paint.color = const Color(0xAA3FA7F5);
      canvas.drawRect(_rect(hintSquare!, sq), paint);
    }
    if (wrongSquare != null) {
      paint.color = const Color(0xAAE04848);
      canvas.drawRect(_rect(wrongSquare!, sq), paint);
    }
    if (checkSquare != null) {
      final r = _rect(checkSquare!, sq);
      paint.shader = RadialGradient(
        colors: const [Color(0xFFFF0000), Color(0x00FF0000)],
        stops: const [0.25, 0.9],
      ).createShader(r);
      canvas.drawRect(r, paint);
      paint.shader = null;
    }

    // Coordinates, chess.com style: ranks on the left file, files on the bottom rank.
    if (showCoordinates) {
      for (int s = 0; s < 64; s++) {
        final col = flipped ? 7 - (s & 7) : (s & 7);
        final row = flipped ? (s >> 3) : 7 - (s >> 3);
        final light = _isLight(s);
        final color = light ? BoardColors.dark : BoardColors.light;
        if (col == 0) {
          _text(canvas, '${(s >> 3) + 1}', color, sq,
              Offset(col * sq + sq * 0.06, row * sq + sq * 0.03), false);
        }
        if (row == 7) {
          _text(canvas, String.fromCharCode(97 + (s & 7)), color, sq,
              Offset((col + 1) * sq - sq * 0.06, (row + 1) * sq - sq * 0.03), true);
        }
      }
    }

    // Legal-move markers.
    for (final t in targets) {
      final r = _rect(t, sq);
      final c = r.center;
      final isCapture = position.board[t] != 0 ||
          (position.ep == t && selected != null &&
              pieceType(position.board[selected!]) == kPawn);
      if (isCapture) {
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sq * 0.09
          ..color = const Color(0x26000000);
        canvas.drawCircle(c, sq * 0.45, ring);
      } else {
        paint.color = const Color(0x26000000);
        canvas.drawCircle(c, sq * 0.17, paint);
      }
    }
  }

  void _text(Canvas canvas, String text, Color color, double sq, Offset anchor,
      bool alignRightBottom) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: sq * 0.22,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = alignRightBottom
        ? Offset(anchor.dx - tp.width, anchor.dy - tp.height)
        : anchor;
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
