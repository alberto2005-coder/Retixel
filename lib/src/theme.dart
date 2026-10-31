import 'package:flutter/material.dart';

/// Retixel palette. Keep in sync with `replica/design/tokens.json`.
const Color kBackground = Color(0xFF0A0C10);
const Color kSurface = Color(0xFF12161D);
const Color kSurfaceAlt = Color(0xFF1A2029);
const Color kText = Color(0xFFF2F5F7);
const Color kMuted = Color(0xFF98A4B3);
const Color kPrimary = Color(0xFF4ADEDE);
const Color kOnPrimary = Color(0xFF04201F);
const Color kAccent = Color(0xFFFFB454);
const Color kSuccess = Color(0xFF66D9A3);
const Color kWarning = Color(0xFFFFC65C);
const Color kDanger = Color(0xFFFF6B6B);

const double kRadius = 14;
const double kGap = 14;

ThemeData buildRetixelTheme() {
  final ColorScheme scheme = const ColorScheme.dark(
    primary: kPrimary,
    onPrimary: kOnPrimary,
    secondary: kAccent,
    onSecondary: Color(0xFF1B1204),
    surface: kSurface,
    onSurface: kText,
    error: kDanger,
    onError: Color(0xFF2A0505),
  );

  final TextTheme text = Typography.material2021(platform: TargetPlatform.windows)
      .white
      .apply(fontFamily: 'Segoe UI', bodyColor: kText, displayColor: kText);

  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    canvasColor: kBackground,
    fontFamily: 'Segoe UI',
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: kMuted, height: 1.35),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    dividerColor: Colors.white12,
    splashFactory: InkSparkle.splashFactory,
    sliderTheme: const SliderThemeData(
      activeTrackColor: kPrimary,
      inactiveTrackColor: kSurfaceAlt,
      thumbColor: kPrimary,
      overlayColor: Color(0x334ADEDE),
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) return kOnPrimary;
        return kMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) return kPrimary;
        return kSurfaceAlt;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? kPrimary : Colors.white24,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: kMuted),
      border: border(Colors.white12),
      enabledBorder: border(Colors.white12),
      focusedBorder: border(kPrimary, 1.5),
      errorBorder: border(kDanger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: kOnPrimary,
        disabledBackgroundColor: kSurfaceAlt,
        disabledForegroundColor: kMuted,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: Colors.white24),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: kMuted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      textStyle: const TextStyle(color: kText, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurfaceAlt,
      contentTextStyle: const TextStyle(color: kText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 520,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      titleTextStyle: const TextStyle(
        color: kText,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(color: kMuted, fontSize: 14, height: 1.4),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(kSurfaceAlt),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kSurfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(Colors.white24),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll<double>(6),
    ),
    focusColor: kPrimary,
  );
}
