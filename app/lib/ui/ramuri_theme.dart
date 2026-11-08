import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_type.dart';

/// Themes der App (FR-0205). `app.dart` setzt [light] und [dark] mit
/// `ThemeMode.system`.
abstract final class RamuriTheme {
  static final ThemeData light = _build(RamuriColors.light, Brightness.light);
  static final ThemeData dark = _build(RamuriColors.night, Brightness.dark);

  /// Mindestgröße von Bedienelementen in dp (FR-0205, vor den 44 px des Designs).
  static const double minTarget = 48;

  static ThemeData _build(RamuriColors c, Brightness brightness) {
    final textTheme = ramuriTextTheme(c);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.tint,
      onPrimaryContainer: c.text,
      secondary: c.action,
      onSecondary: c.onAction,
      secondaryContainer: c.tint,
      onSecondaryContainer: c.text,
      tertiary: c.accent,
      onTertiary: c.onAccent,
      error: c.danger,
      onError: c.onDanger,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.track,
      surfaceContainerHighest: c.track,
      outline: c.outlineStrong,
      outlineVariant: c.outline,
      inverseSurface: c.panel,
      onInverseSurface: c.onPanel,
      inversePrimary: c.action,
    );

    const pill = StadiumBorder();
    const buttonSize = Size(64, 56);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 22);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: ramuriBodyFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [c, RamuriType.from(c)],
      dividerColor: c.outline,
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.text),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.track,
        circularTrackColor: c.track,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.action,
          foregroundColor: c.onAction,
          disabledBackgroundColor: c.track,
          disabledForegroundColor: c.textMuted,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          disabledForegroundColor: c.textMuted,
          side: BorderSide(color: c.outlineStrong, width: 1.5),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: pill,
          textStyle: textTheme.labelMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(minTarget, minTarget),
          shape: pill,
          textStyle: textTheme.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        labelStyle: textTheme.bodySmall,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: c.accent),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(color: c.danger),
        border: _inputBorder(c.outline),
        enabledBorder: _inputBorder(c.outline),
        focusedBorder: _inputBorder(c.accent, width: 2),
        errorBorder: _inputBorder(c.danger),
        focusedErrorBorder: _inputBorder(c.danger, width: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.tint,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? textTheme.labelSmall?.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                )
              : textTheme.labelSmall,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? c.text : c.textMuted,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.track,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.outlineStrong,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.panel,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.onPanel),
        actionTextColor: c.action,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}
