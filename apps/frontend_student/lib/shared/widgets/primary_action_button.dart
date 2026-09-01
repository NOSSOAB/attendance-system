import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrimaryActionButton extends StatelessWidget {
  static const continueLabel = 'Ti\u1EBFp t\u1EE5c';

  final String label;
  final VoidCallback? onPressed;

  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF165DFF),
          disabledBackgroundColor: const Color(0xFFC7D2E5),
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.beVietnamPro(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.0,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
