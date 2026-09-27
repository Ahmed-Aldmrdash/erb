// Renders the launcher icon with Flutter and writes the Android mipmaps:
//   flutter test tool/app_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _green = Color(0xFF0E6B5C);
const _greenDark = Color(0xFF094A40);

/// Full-bleed artwork (square, 108 x 108 design units like an adaptive icon).
class IconArt extends StatelessWidget {
  const IconArt({super.key, this.foregroundOnly = false, this.rounded = false});

  final bool foregroundOnly;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final fg = LayoutBuilder(
      builder: (context, c) {
        final u = c.maxWidth / 108;
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 20 * u,
              top: 22 * u,
              child: Icon(Icons.grass_rounded, size: 42 * u, color: const Color(0xFFE8F5C8)),
            ),
            Positioned(
              right: 20 * u,
              bottom: 20 * u,
              child: Icon(Icons.kitchen_rounded, size: 40 * u, color: Colors.white),
            ),
            Positioned(
              right: 22 * u,
              top: 22 * u,
              child: Container(
                width: 18 * u,
                height: 18 * u,
                decoration: const BoxDecoration(color: Color(0xFFF2B233), shape: BoxShape.circle),
              ),
            ),
            Positioned(
              left: 24 * u,
              bottom: 24 * u,
              child: Container(
                width: 26 * u,
                height: 6 * u,
                decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(3 * u)),
              ),
            ),
          ],
        );
      },
    );
    if (foregroundOnly) return fg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(rounded ? 1000 : 0),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_green, _greenDark],
          ),
        ),
        child: fg,
      ),
    );
  }
}

Future<void> _loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final font = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final loader = FontLoader('MaterialIcons')..addFont(font.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

Future<void> _render(WidgetTester tester, Widget art, int px, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: SizedBox(width: 300, height: 300, child: art)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: px / 300);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File(path)..parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('launcher icons', (tester) async {
    await tester.runAsync(_loadIconFont);
    const res = 'android/app/src/main/res';
    const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final e in legacy.entries) {
      await _render(tester, const IconArt(rounded: true), e.value, '$res/mipmap-${e.key}/ic_launcher.png');
      // Adaptive icon foreground: 108dp canvas.
      await _render(tester, const IconArt(foregroundOnly: true), e.value * 108 ~/ 48, '$res/mipmap-${e.key}/ic_launcher_foreground.png');
    }
    await _render(tester, const IconArt(), 512, 'assets/images/logo.png');
  });
}
