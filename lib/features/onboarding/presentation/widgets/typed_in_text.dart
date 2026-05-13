import 'package:flutter/material.dart';

/// Reveals a string one character at a time on first build.
///
/// Animation runs once (no loop) at ~50 ms per character, capped by an
/// overall maximum so very long strings still complete inside the
/// onboarding entry budget.
class TypedInText extends StatefulWidget {
  const TypedInText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.perCharacter = const Duration(milliseconds: 50),
    this.maxDuration = const Duration(milliseconds: 1200),
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration perCharacter;
  final Duration maxDuration;

  @override
  State<TypedInText> createState() => _TypedInTextState();
}

class _TypedInTextState extends State<TypedInText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final desired = widget.perCharacter * widget.text.characters.length;
    final clamped = desired > widget.maxDuration ? widget.maxDuration : desired;
    _controller = AnimationController(
      vsync: this,
      duration: clamped == Duration.zero
          ? const Duration(milliseconds: 1)
          : clamped,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant TypedInText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final visible = (chars.length * _controller.value).round();
        final shown = chars.take(visible).join();
        // Reserve full layout space so the surrounding Column doesn't
        // jump as characters reveal.
        return Stack(
          children: [
            Opacity(
              opacity: 0,
              child: Text(
                widget.text,
                textAlign: widget.textAlign,
                style: widget.style,
              ),
            ),
            Text(shown, textAlign: widget.textAlign, style: widget.style),
          ],
        );
      },
    );
  }
}
