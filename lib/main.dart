import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const CleanCrosshairApp());
}

class CleanCrosshairApp extends StatelessWidget {
  const CleanCrosshairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanCrosshair',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
        primaryColor: const Color(0xFF00FF66),
      ),
      home: const CrosshairControlPanel(),
    );
  }
}

class CrosshairControlPanel extends StatefulWidget {
  const CrosshairControlPanel({super.key});

  @override
  State<CrosshairControlPanel> createState() => _CrosshairControlPanelState();
}

class _CrosshairControlPanelState extends State<CrosshairControlPanel> {
  double _size = 20.0;
  double _thickness = 2.0;
  Color _color = const Color(0xFF00FF66);
  String _shape = 'Cross';
  bool _isOverlayActive = false;

  final List<Color> _presetColors = [
    const Color(0xFF00FF66),
    const Color(0xFFFF0055),
    const Color(0xFF00FFFF),
    const Color(0xFFFFFF00),
    const Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CleanCrosshair — Panel de Control'),
        backgroundColor: const Color(0xFF18181B),
        elevation: 0,
      ),
      body: Row(
        children: [
          // Panel de configuración izquierdo
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              color: const Color(0xFF18181B),
              child: ListView(
                children: [
                  const Text(
                    'Configuración de la Mira',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text('Estilo de Mira',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: _shape,
                    dropdownColor: const Color(0xFF27272A),
                    isExpanded: true,
                    items: ['Cross', 'Dot', 'Circle'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value,
                            style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _shape = newValue!;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('Tamaño: ${_size.toInt()}px',
                      style: const TextStyle(color: Colors.grey)),
                  Slider(
                    value: _size,
                    min: 5,
                    max: 60,
                    activeColor: const Color(0xFF00FF66),
                    onChanged: (value) {
                      setState(() {
                        _size = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('Grosor: ${_thickness.toInt()}px',
                      style: const TextStyle(color: Colors.grey)),
                  Slider(
                    value: _thickness,
                    min: 1,
                    max: 10,
                    activeColor: const Color(0xFF00FF66),
                    onChanged: (value) {
                      setState(() {
                        _thickness = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Color de la Mira',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _presetColors.map((color) {
                      return GestureDetector(
                        onTap: () => setState(() => _color = color),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == color
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOverlayActive
                          ? Colors.redAccent
                          : const Color(0xFF00FF66),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async {
                      setState(() {
                        _isOverlayActive = !_isOverlayActive;
                      });

                      if (_isOverlayActive) {
                        // Activar modo overlay flotante sin bordes y encima de todo
                        await windowManager.setAsFrameless();
                        await windowManager.setAlwaysOnTop(true);
                        await windowManager.setSize(const Size(200, 200));
                        await windowManager.center();
                      } else {
                        // Restaurar panel de control principal
                        await windowManager.setAlwaysOnTop(false);
                        await windowManager.setSize(const Size(900, 600));
                        await windowManager.center();
                      }
                    },
                    icon: Icon(_isOverlayActive
                        ? Icons.visibility_off
                        : Icons.visibility),
                    label: Text(
                      _isOverlayActive
                          ? 'Restaurar Panel de Control'
                          : 'Activar Overlay Flotante',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Vista previa derecha
          Expanded(
            flex: 1,
            child: Container(
              color: const Color(0xFF09090B),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GridPainter(),
                    ),
                  ),
                  const Text(
                    'Vista Previa en Tiempo Real',
                    style: TextStyle(color: Colors.white24, fontSize: 14),
                  ),
                  CustomPaint(
                    painter: CrosshairPainter(
                      shape: _shape,
                      size: _size,
                      thickness: _thickness,
                      color: _color,
                    ),
                    size: const Size(100, 100),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CrosshairPainter extends CustomPainter {
  final String shape;
  final double size;
  final double thickness;
  final Color color;

  CrosshairPainter({
    required this.shape,
    required this.size,
    required this.thickness,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = this.size / 2;

    if (shape == 'Cross') {
      canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        paint,
      );
    } else if (shape == 'Dot') {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, thickness * 1.5, dotPaint);
    } else if (shape == 'Circle') {
      canvas.drawCircle(center, radius, paint);
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 1.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}