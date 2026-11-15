import 'package:flutter/material.dart';

import '../theme.dart';

/// Grows/fades a list item in when [appear] is true on first build, and
/// collapses/fades it out when [removing] flips to true.
class AnimatedEntry extends StatefulWidget {
  const AnimatedEntry({
    super.key,
    required this.child,
    this.appear = false,
    this.removing = false,
  });

  final Widget child;
  final bool appear;
  final bool removing;

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kAnimMedium,
    value: widget.appear && !widget.removing ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.appear) _c.forward();
    if (widget.removing) _c.reverse();
  }

  @override
  void didUpdateWidget(AnimatedEntry old) {
    super.didUpdateWidget(old);
    if (widget.removing && !old.removing) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(_curve),
          child: widget.child,
        ),
      ),
    );
  }
}
