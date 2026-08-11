import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const nexusBlue = Color(0xff0738f9);
const nexusPink = Color(0xffffc9f5);
const nexusCream = Color(0xfffffcf4);

class NexusLogo extends StatelessWidget {
  const NexusLogo({super.key, this.size = 42, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/branding/nexus.svg',
        width: size,
        height: size,
        colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
        semanticsLabel: 'Nexus One',
      );
}

class NexusWordmark extends StatelessWidget {
  const NexusWordmark({super.key, this.onBlue = false, this.compact = false});
  final bool onBlue;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NexusLogo(size: compact ? 30 : 40, color: onBlue ? Colors.white : null),
          const SizedBox(width: 12),
          Text(
            'Nexus One',
            style: TextStyle(
              color: onBlue ? Colors.white : Colors.black,
              fontSize: compact ? 18 : 25,
              fontWeight: FontWeight.w500,
              letterSpacing: -.6,
            ),
          ),
        ],
      );
}
