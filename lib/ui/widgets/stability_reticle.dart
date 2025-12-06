import 'package:flutter/material.dart';
import '../../theme/palette.dart';

class StabilityReticle extends StatelessWidget {
  const StabilityReticle({super.key, required this.isStable});

  final bool isStable;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isStable ? Colors.green : Colors.red,
          width: 4,
        ),
        color: (isStable ? Palette.mint : Palette.peach).withOpacity(0.4),
      ),
      child: Center(
        child: Icon(
          isStable ? Icons.check : Icons.warning_amber_rounded,
          color: Palette.deepText,
        ),
      ),
    );
  }
}
