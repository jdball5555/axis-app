import 'dart:math';
import 'package:flutter/material.dart';

class ColorWheelPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorWheelPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late HSVColor _currentHSV;

  @override
  void initState() {
    super.initState();
    _currentHSV = HSVColor.fromColor(widget.initialColor);
  }

  void _onPanUpdate(Offset localPosition, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    final radius = size.width / 2;
    final dist = sqrt(dx * dx + dy * dy);

    double saturation = (dist / radius).clamp(0.0, 1.0);

    double angle = atan2(dy, dx);
    if (angle < 0) angle += 2 * pi;
    double hue = (angle / (2 * pi)) * 360;

    setState(() {
      _currentHSV = HSVColor.fromAHSV(1.0, hue, saturation, 1.0);
    });

    widget.onColorChanged(_currentHSV.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanUpdate: (details) =>
              _onPanUpdate(details.localPosition, constraints.biggest),
          onTapDown: (details) =>
              _onPanUpdate(details.localPosition, constraints.biggest),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: ColorWheelPainter(_currentHSV),
          ),
        );
      },
    );
  }
}

class ColorWheelPainter extends CustomPainter {
  final HSVColor selectedColor;

  ColorWheelPainter(this.selectedColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final hueSweep = SweepGradient(
      colors: [
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.green,
        Colors.cyan,
        Colors.blue,
        Colors.purple,
        Colors.pink,
        Colors.red,
      ],
      stops: const [0.0, 0.1, 0.2, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0],
    );

    final huePaint = Paint()..shader = hueSweep.createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final satRadial = RadialGradient(
      colors: [Colors.white, Colors.transparent],
    );
    final satPaint = Paint()..shader = satRadial.createShader(rect);
    canvas.drawCircle(center, radius, satPaint);

    final hueAngle = (selectedColor.hue / 360) * 2 * pi;
    final saturationRadius = selectedColor.saturation * radius;

    final selectorOffset = Offset(
      center.dx + saturationRadius * cos(hueAngle),
      center.dy + saturationRadius * sin(hueAngle),
    );

    canvas.drawCircle(selectorOffset, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
      selectorOffset,
      12,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      selectorOffset,
      8,
      Paint()..color = selectedColor.toColor(),
    );
  }

  @override
  bool shouldRepaint(ColorWheelPainter oldDelegate) {
    return oldDelegate.selectedColor != selectedColor;
  }
}
