import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum AppBreakpoint {
  compact,
  medium,
  expanded,
}

class AppResponsive {
  final double width;
  final double height;
  final AppBreakpoint breakpoint;

  const AppResponsive._({
    required this.width,
    required this.height,
    required this.breakpoint,
  });

  factory AppResponsive.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;

    final AppBreakpoint breakpoint;
    if (width >= 1080) {
      breakpoint = AppBreakpoint.expanded;
    } else if (width >= 720) {
      breakpoint = AppBreakpoint.medium;
    } else {
      breakpoint = AppBreakpoint.compact;
    }

    return AppResponsive._(
      width: width,
      height: size.height,
      breakpoint: breakpoint,
    );
  }

  bool get isCompact => breakpoint == AppBreakpoint.compact;
  bool get isMedium => breakpoint == AppBreakpoint.medium;
  bool get isExpanded => breakpoint == AppBreakpoint.expanded;

  double get pageHorizontalPadding {
    if (isExpanded) {
      return 28;
    }
    if (isMedium) {
      return 22;
    }
    return 14;
  }

  double get contentMaxWidth {
    if (isExpanded) {
      return 1120;
    }
    if (isMedium) {
      return 920;
    }
    return 680;
  }

  double sectionGap(
      {double compact = 10, double medium = 12, double expanded = 14}) {
    if (isExpanded) {
      return expanded;
    }
    if (isMedium) {
      return medium;
    }
    return compact;
  }

  double scale(double value) {
    final ratio = width / 390;
    final clamped = ratio.clamp(0.9, 1.15);
    return value * clamped;
  }

  double clampWidth(double minWidth, double preferredWidth, double maxWidth) {
    return math.max(minWidth, math.min(preferredWidth, maxWidth));
  }
}
