import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/util/format.dart';
import '../../ui/theme.dart';

/// Opens a live camera that continuously scans for barcodes. Returns the first barcode it reads.
Future<String?> scanBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _CodeReaderPage()));

class _CodeReaderPage extends StatefulWidget {
  const _CodeReaderPage();

  @override
  State<_CodeReaderPage> createState() => _CodeReaderPageState();
}

class _CodeReaderPageState extends State<_CodeReaderPage> {
  final MobileScannerController _controller = MobileScannerController();
  final _manual = TextEditingController();
  bool _done = false;
  bool _torch = false;
  bool _showManual = false;
  String? _lastRead;
  final String _status = 'وجّه الكاميرا على الباركود';

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _toggleTorch() {
    _torch = !_torch;
    _controller.toggleTorch();
    setState(() {});
  }

  void _submitManual() {
    final code = normalizeDigits(_manual.text.trim());
    if (code.isEmpty) return;
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_status, style: const TextStyle(color: Colors.white, fontSize: 15)),
          actions: [
            IconButton(
              onPressed: _toggleTorch,
              icon: Icon(_torch ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
              tooltip: 'الكشاف',
            ),
            IconButton(
              onPressed: () => setState(() => _showManual = !_showManual),
              icon: const Icon(Icons.keyboard_outlined),
              tooltip: 'كتابة يدوي',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      if (_done) return;
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                        final code = barcodes.first.rawValue!;
                        if (!_done && mounted) {
                          setState(() => _lastRead = code);
                          _done = true;
                          HapticFeedback.mediumImpact();
                          // Small delay so user sees what was read.
                          final nav = Navigator.of(context);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) nav.pop(code);
                          });
                        }
                      }
                    },
                  ),
                  // Overlay box.
                  IgnorePointer(
                    child: Container(
                      width: 260,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _lastRead != null ? AppColors.good : Colors.white,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _lastRead != null
                          ? Center(
                              child: Text(
                                _lastRead!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (_showManual)
              Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(color: Colors.white, fontSize: 20),
                        decoration: const InputDecoration(
                          hintText: 'اكتب رقم الكود',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onSubmitted: (_) => _submitManual(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _submitManual,
                      child: const Text('ابحث'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
