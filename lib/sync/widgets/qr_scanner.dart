// lib/sync/widgets/sync_qr_scanner.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:i_gen/sync/sync_qr.dart';

class SyncQrScanner extends StatefulWidget {
  const SyncQrScanner({super.key, required this.onScanned});

  final void Function(SyncQrData data) onScanned;

  @override
  State<SyncQrScanner> createState() => _SyncQrScannerState();
}

class _SyncQrScannerState extends State<SyncQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      final qrData = SyncQrData.decode(rawValue);
      if (qrData != null) {
        _hasScanned = true;
        widget.onScanned(qrData);
        Navigator.of(context).pop();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Overlay with scanning frame
          _ScannerOverlay(colors: colors),

          // Instructions at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Point your camera at the QR code shown on the receiving device',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final left = (constraints.maxWidth - scanAreaSize) / 2;
        final top = (constraints.maxHeight - scanAreaSize) / 2 - 50;

        return Stack(
          children: [
            // Darkened background
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scanning frame border
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: scanAreaSize,
                height: scanAreaSize,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.primary, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            // Corner accents
            ..._buildCorners(left, top, scanAreaSize, colors.primary),
          ],
        );
      },
    );
  }

  List<Widget> _buildCorners(
    double left,
    double top,
    double size,
    Color color,
  ) {
    const cornerSize = 24.0;
    const cornerWidth = 4.0;

    return [
      // Top-left
      Positioned(
        left: left - cornerWidth / 2,
        top: top - cornerWidth / 2,
        child: _Corner(
          size: cornerSize,
          width: cornerWidth,
          color: color,
          rotation: 0,
        ),
      ),
      // Top-right
      Positioned(
        right: left - cornerWidth / 2,
        top: top - cornerWidth / 2,
        child: _Corner(
          size: cornerSize,
          width: cornerWidth,
          color: color,
          rotation: 90,
        ),
      ),
      // Bottom-right
      Positioned(
        right: left - cornerWidth / 2,
        bottom: top - cornerWidth / 2,
        child: _Corner(
          size: cornerSize,
          width: cornerWidth,
          color: color,
          rotation: 180,
        ),
      ),
      // Bottom-left
      Positioned(
        left: left - cornerWidth / 2,
        bottom: top - cornerWidth / 2,
        child: _Corner(
          size: cornerSize,
          width: cornerWidth,
          color: color,
          rotation: 270,
        ),
      ),
    ];
  }
}

class _Corner extends StatelessWidget {
  const _Corner({
    required this.size,
    required this.width,
    required this.color,
    required this.rotation,
  });

  final double size;
  final double width;
  final Color color;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: rotation ~/ 90,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerPainter(color: color, strokeWidth: width),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
