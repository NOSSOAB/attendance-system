import 'package:flutter/material.dart';

PageRoute<T> buildAppPageRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final primary = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final secondary = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final enterSlide = Tween<Offset>(
        begin: const Offset(0.028, 0),
        end: Offset.zero,
      ).animate(primary);
      final exitSlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.014, 0),
      ).animate(secondary);
      final enterFade = Tween<double>(begin: 0.0, end: 1.0).animate(primary);
      final exitFade = Tween<double>(begin: 1.0, end: 0.96).animate(secondary);

      return FadeTransition(
        opacity: exitFade,
        child: SlideTransition(
          position: exitSlide,
          child: FadeTransition(
            opacity: enterFade,
            child: SlideTransition(position: enterSlide, child: child),
          ),
        ),
      );
    },
  );
}
