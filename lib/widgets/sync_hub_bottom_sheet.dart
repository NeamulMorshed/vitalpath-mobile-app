/// sync_hub_bottom_sheet.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The "Sync New Doctor" dual-option bottom sheet.
///
/// Blueprint §1.1 / §7 — Doctor-Patient Handshake:
///   "Implement a 'Sync New Doctor' button that opens a dual-option view:
///    'Enter 6-Digit Code' or 'Scan QR Code'."
///
/// Layout:
///   ┌──────────────────────────────────────┐
///   │  Handle / header                      │
///   │  [Code]  [QR Scan]  ← TabBar         │
///   ├──────────────────────────────────────┤
///   │  Code tab:  □ □ □ □ □ □              │
///   │             [Connect Doctor]          │
///   ├──────────────────────────────────────┤
///   │  QR tab:   ┌──────────┐              │
///   │            │ Camera   │              │
///   │            └──────────┘              │
///   └──────────────────────────────────────┘
///
/// QR format: "vitalpath://sync/{6-digit-code}"
///
/// Dependencies:
///   mobile_scanner: ^5.0.0   ← add to pubspec.yaml for QR tab
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/models/doctor_model.dart';
import 'package:vitalpath/providers/doctor_provider.dart';
import 'package:vitalpath/services/doctor_sync_service.dart';
import 'package:vitalpath/services/haptic_service.dart';

// ── Public entry point ────────────────────────────────────────────────────────
class SyncHubBottomSheet extends StatefulWidget {
  final DoctorProvider doctorProvider;
  final String patientId;
  final void Function(DoctorModel linked) onSyncSuccess;

  const SyncHubBottomSheet({
    super.key,
    required this.doctorProvider,
    required this.patientId,
    required this.onSyncSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required DoctorProvider doctorProvider,
    required String patientId,
    required void Function(DoctorModel linked) onSyncSuccess,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SyncHubBottomSheet(
        doctorProvider: doctorProvider,
        patientId: patientId,
        onSyncSuccess: onSyncSuccess,
      ),
    );
  }

  @override
  State<SyncHubBottomSheet> createState() => _SyncHubBottomSheetState();
}

class _SyncHubBottomSheetState extends State<SyncHubBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.90,
        expand: false,
        builder: (_, sc) => _buildBody(sc),
      ),
    );
  }

  Widget _buildBody(ScrollController sc) {
    return Column(
      children: [
        // ── Handle + header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F7F4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sync_rounded,
                        color: Color(0xFF00897B), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync New Doctor',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'Enter a code or scan a QR from your doctor',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF9E9E9E)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),

        // ── Tab bar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: const Color(0xFF00897B),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF9E9E9E),
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Enter Code'),
                Tab(text: 'Scan QR'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 4),

        // ── Tab views ────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _CodeTab(
                doctorProvider: widget.doctorProvider,
                patientId: widget.patientId,
                onSyncSuccess: (linked) {
                  Navigator.of(context).pop();
                  widget.onSyncSuccess(linked);
                },
              ),
              _QrTab(
                doctorProvider: widget.doctorProvider,
                patientId: widget.patientId,
                onSyncSuccess: (linked) {
                  Navigator.of(context).pop();
                  widget.onSyncSuccess(linked);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Code tab ──────────────────────────────────────────────────────────────────
class _CodeTab extends StatefulWidget {
  final DoctorProvider doctorProvider;
  final String patientId;
  final void Function(DoctorModel) onSyncSuccess;

  const _CodeTab({
    required this.doctorProvider,
    required this.patientId,
    required this.onSyncSuccess,
  });

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab>
    with SingleTickerProviderStateMixin {
  static const _length = 6;
  final _controllers =
      List.generate(_length, (_) => TextEditingController());
  final _focusNodes = List.generate(_length, (_) => FocusNode());

  bool _isSubmitting = false;
  String? _error;
  bool _showSuccess = false;

  // Shake animation for invalid code
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shakeCtrl.dispose();
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();
  bool get _isComplete => _code.length == _length;

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      // Backspace — move focus back.
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }

    // Support paste: distribute characters across remaining boxes.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < digits.length && index + i < _length; i++) {
        _controllers[index + i].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, _length - 1);
      _focusNodes[next].requestFocus();
      setState(() {});
      if (_isComplete) _submit();
      return;
    }

    // Single digit: advance focus.
    _controllers[index].text = value;
    setState(() {});
    if (index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (_isComplete) {
      _focusNodes[index].unfocus();
      _submit();
    }
  }

  Future<void> _submit() async {
    if (!_isComplete || _isSubmitting) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final linked = await widget.doctorProvider.syncByCode(
        patientId: widget.patientId,
        code: _code,
      );

      await HapticService().goalSuccess();
      setState(() => _showSuccess = true);

      await Future.delayed(const Duration(milliseconds: 900));
      widget.onSyncSuccess(linked);
    } on DoctorSyncException catch (e) {
      setState(() => _error = e.message);
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
      // Clear boxes on invalid code so user can retype.
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        children: [
          // ── Success state ────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showSuccess
                ? _SuccessState(key: const ValueKey('success'))
                : _buildCodeInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeInput() {
    return Column(
      key: const ValueKey('input'),
      children: [
        const Text(
          'Ask your doctor for their 6-digit code',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF9E9E9E),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),

        // ── 6-digit boxes ──────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_length, (i) {
              final isActive = _focusNodes[i].hasFocus;
              final hasValue = _controllers[i].text.isNotEmpty;
              return _DigitBox(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                isActive: isActive,
                hasValue: hasValue,
                hasError: _error != null,
                onChanged: (v) => _onDigitChanged(i, v),
                onTap: () {
                  _controllers[i].clear();
                  setState(() {});
                },
              );
            }),
          ),
        ),

        // ── Error message ──────────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: Color(0xFFE53935)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFFE53935)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 28),

        // ── CTA button ─────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: (_isComplete && !_isSubmitting) ? _submit : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link_rounded, size: 18),
            label: Text(
              _isSubmitting ? 'Connecting…' : 'Connect Doctor',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              disabledBackgroundColor: const Color(0xFFB2DFDB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Digit input box ───────────────────────────────────────────────────────────
class _DigitBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isActive;
  final bool hasValue;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.isActive,
    required this.hasValue,
    required this.hasError,
    required this.onChanged,
    required this.onTap,
  });

  @override
  State<_DigitBox> createState() => _DigitBoxState();
}

class _DigitBoxState extends State<_DigitBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = widget.focusNode.hasFocus;
    Color borderColor;
    if (widget.hasError) {
      borderColor = const Color(0xFFE53935);
    } else if (isFocused) {
      borderColor = const Color(0xFF00897B);
    } else if (widget.hasValue) {
      borderColor = const Color(0xFF00897B).withOpacity(0.4);
    } else {
      borderColor = const Color(0xFFE0E0E0);
    }

    return Container(
      width: 44,
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFFE6F7F4)
            : widget.hasValue
                ? const Color(0xFFF0FAF8)
                : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isFocused ? 2 : 1.5),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 6, // allows paste of full code
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Color(0xFF00897B),
          letterSpacing: 1,
        ),
        onChanged: widget.onChanged,
        onTap: widget.onTap,
      ),
    );
  }
}

// ── QR tab ────────────────────────────────────────────────────────────────────
class _QrTab extends StatefulWidget {
  final DoctorProvider doctorProvider;
  final String patientId;
  final void Function(DoctorModel) onSyncSuccess;

  const _QrTab({
    required this.doctorProvider,
    required this.patientId,
    required this.onSyncSuccess,
  });

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  bool _isProcessing = false;
  bool _showSuccess = false;
  String? _error;

  // ── Scan handler ───────────────────────────────────────────────────────────
  // Wired to MobileScanner.onDetect in the real implementation.
  // MobileScanner import: 'package:mobile_scanner/mobile_scanner.dart'
  //
  // Usage:
  //   MobileScanner(
  //     onDetect: (capture) {
  //       final barcode = capture.barcodes.first;
  //       final raw = barcode.rawValue;
  //       if (raw != null) _onQrDetected(raw);
  //     },
  //   )
  Future<void> _onQrDetected(String payload) async {
    if (_isProcessing || _showSuccess) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final linked = await widget.doctorProvider.syncByQr(
        patientId: widget.patientId,
        qrPayload: payload,
      );

      await HapticService().goalSuccess();
      setState(() => _showSuccess = true);

      await Future.delayed(const Duration(milliseconds: 900));
      widget.onSyncSuccess(linked);
    } on DoctorSyncException catch (e) {
      setState(() => _error = e.message);
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSuccess) {
      return const Center(child: _SuccessState());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        children: [
          const Text(
            'Point your camera at your doctor\'s QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9E9E9E),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // ── Camera viewfinder ──────────────────────────────────────────────
          // Replace this placeholder with:
          //   ClipRRect(
          //     borderRadius: BorderRadius.circular(18),
          //     child: SizedBox(
          //       height: 260,
          //       child: MobileScanner(onDetect: (c) {
          //         final raw = c.barcodes.first.rawValue;
          //         if (raw != null) _onQrDetected(raw);
          //       }),
          //     ),
          //   )
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Corner frame overlay
                CustomPaint(
                  size: const Size(200, 200),
                  painter: _QrFramePainter(),
                ),
                if (_isProcessing)
                  const CircularProgressIndicator(
                      color: Color(0xFF00897B))
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Camera not available in preview.\nAdd mobile_scanner to pubspec.yaml.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      // Debug shortcut: simulate a QR scan
                      TextButton(
                        onPressed: () => _onQrDetected(
                            'vitalpath://sync/123456'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00897B),
                          backgroundColor:
                              const Color(0xFF00897B).withOpacity(0.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Simulate QR Scan (debug)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Error message ────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: Color(0xFFE53935)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFE53935)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── QR frame painter ──────────────────────────────────────────────────────────
class _QrFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 24.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawPath(
        Path()
          ..moveTo(0, corner)
          ..lineTo(0, 0)
          ..lineTo(corner, 0),
        paint);
    // Top-right
    canvas.drawPath(
        Path()
          ..moveTo(w - corner, 0)
          ..lineTo(w, 0)
          ..lineTo(w, corner),
        paint);
    // Bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(0, h - corner)
          ..lineTo(0, h)
          ..lineTo(corner, h),
        paint);
    // Bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(w - corner, h)
          ..lineTo(w, h)
          ..lineTo(w, h - corner),
        paint);
  }

  @override
  bool shouldRepaint(_QrFramePainter _) => false;
}

// ── Shared success state ──────────────────────────────────────────────────────
class _SuccessState extends StatelessWidget {
  const _SuccessState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 40, color: Color(0xFF00897B)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Doctor Connected!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your doctor is now linked.\nThey\'ll appear at the top of your list.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Color(0xFF9E9E9E), height: 1.5),
          ),
        ],
      ),
    );
  }
}
