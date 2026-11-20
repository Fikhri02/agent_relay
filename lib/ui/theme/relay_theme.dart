import 'package:flutter/material.dart';

/// Direction C ("Memo desk") colours that ThemeData has no slot for.
///
/// Palette: iris-slate. The chrome strip and its tabs are dark in both modes.
@immutable
class RelayColors extends ThemeExtension<RelayColors> {
  const RelayColors({
    required this.chrome,
    required this.chromeText,
    required this.tab,
    required this.tabText,
    required this.tabCount,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.outline,
    required this.muted,
    required this.primaryText,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.people,
  });

  /// Top strip that holds the conversation tabs.
  final Color chrome;
  final Color chromeText;

  /// Inactive tab fill and label. The active tab uses the page background.
  final Color tab;
  final Color tabText;

  /// Unread count on an inactive tab (primary as text is too dark on [tab]).
  final Color tabCount;

  /// Memo and card fill on the page background.
  final Color surface;
  final Color surfaceRaised;
  final Color line;
  final Color outline;
  final Color muted;

  /// Primary used as text on the page background or a surface.
  final Color primaryText;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// One colour per teammate on their memos (name and initial disc). A
  /// person keeps the same colour everywhere: it is picked from their device
  /// id. My own memos use [primaryText]. Readable as text on the page and on
  /// a memo, and [surface] is readable on each as the disc's initial.
  final List<Color> people;

  /// The colour for one sender: [primaryText] for my own memos, otherwise a
  /// stable pick from [people] for [deviceId].
  Color person(String deviceId, {bool mine = false}) {
    if (mine || people.isEmpty) return primaryText;
    var h = 0x811c9dc5; // FNV-1a, so the pick is the same on every Mac
    for (final unit in deviceId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return people[h % people.length];
  }

  static RelayColors of(BuildContext context) =>
      Theme.of(context).extension<RelayColors>()!;

  static const light = RelayColors(
    chrome: Color(0xFF12131A),
    chromeText: Color(0xFFEDEEF2),
    tab: Color(0xFF1E2030),
    tabText: Color(0xFFC6C9D4),
    tabCount: Color(0xFFA5A4FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    line: Color(0xFFE3E5EB),
    outline: Color(0xFF8A90A2),
    muted: Color(0xFF555B6E),
    primaryText: Color(0xFF4F4FCB),
    success: Color(0xFF18794E),
    warning: Color(0xFF975A00),
    danger: Color(0xFFC62A2F),
    info: Color(0xFF0D6AB5),
    people: [
      Color(0xFF0E7C70), // teal
      Color(0xFF975A00), // amber
      Color(0xFFB0306A), // rose
      Color(0xFF1D6BAE), // blue
      Color(0xFF2E7D32), // green
    ],
  );

  static const dark = RelayColors(
    chrome: Color(0xFF06070A),
    chromeText: Color(0xFFEDEEF2),
    tab: Color(0xFF14151C),
    tabText: Color(0xFF9A9FAE),
    tabCount: Color(0xFFA5A4FA),
    surface: Color(0xFF131419),
    surfaceRaised: Color(0xFF1A1C23),
    line: Color(0xFF23252E),
    outline: Color(0xFF5D6272),
    muted: Color(0xFF9A9FAE),
    primaryText: Color(0xFFA5A4FA),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFF1B544),
    danger: Color(0xFFFF6369),
    info: Color(0xFF70B8FF),
    people: [
      Color(0xFF4FD1C1), // teal
      Color(0xFFF1B544), // amber
      Color(0xFFFF7EB0), // rose
      Color(0xFF70B8FF), // blue
      Color(0xFF7EDC8A), // green
    ],
  );

  @override
  RelayColors copyWith({
    Color? chrome,
    Color? chromeText,
    Color? tab,
    Color? tabText,
    Color? tabCount,
    Color? surface,
    Color? surfaceRaised,
    Color? line,
    Color? outline,
    Color? muted,
    Color? primaryText,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    List<Color>? people,
  }) => RelayColors(
    chrome: chrome ?? this.chrome,
    chromeText: chromeText ?? this.chromeText,
    tab: tab ?? this.tab,
    tabText: tabText ?? this.tabText,
    tabCount: tabCount ?? this.tabCount,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    line: line ?? this.line,
    outline: outline ?? this.outline,
    muted: muted ?? this.muted,
    primaryText: primaryText ?? this.primaryText,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
    people: people ?? this.people,
  );

  @override
  RelayColors lerp(RelayColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RelayColors(
      chrome: l(chrome, other.chrome),
      chromeText: l(chromeText, other.chromeText),
      tab: l(tab, other.tab),
      tabText: l(tabText, other.tabText),
      tabCount: l(tabCount, other.tabCount),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      line: l(line, other.line),
      outline: l(outline, other.outline),
      muted: l(muted, other.muted),
      primaryText: l(primaryText, other.primaryText),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      people: [
        for (var i = 0; i < people.length; i++)
          i < other.people.length ? l(people[i], other.people[i]) : people[i],
      ],
    );
  }
}

/// Text styles shared by the screens. Nothing is smaller than 12.
abstract final class RelayText {
  static const tabular = [FontFeature.tabularFigures()];

  /// Mono for the Ref line (SF Mono is not addressable by name; Menlo is).
  static const monoFamily = 'Menlo';
  static const monoFallback = ['SF Mono', 'Monaco', 'Courier'];

  static TextStyle mono(Color color) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 12,
    height: 1.4,
    color: color,
  );
}

abstract final class RelayTheme {
  static const _buttonRadius = 8.0;
  static const _cardRadius = 12.0;
  static const _dialogRadius = 16.0;

  static ThemeData light() => _build(
    brightness: Brightness.light,
    bg: const Color(0xFFF7F8FA),
    text: const Color(0xFF0F1222),
    primary: const Color(0xFF4F4FCB),
    primaryHover: const Color(0xFF4040B0),
    onPrimary: const Color(0xFFFFFFFF),
    colors: RelayColors.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    bg: const Color(0xFF0B0C10),
    text: const Color(0xFFEDEEF2),
    primary: const Color(0xFF8E8CF7),
    primaryHover: const Color(0xFFA5A4FA),
    onPrimary: const Color(0xFF0B0C1F),
    colors: RelayColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color text,
    required Color primary,
    required Color primaryHover,
    required Color onPrimary,
    required RelayColors colors,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      error: colors.danger,
      onError: brightness == Brightness.light ? Colors.white : bg,
      surface: bg,
      onSurface: text,
      onSurfaceVariant: colors.muted,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceRaised,
      surfaceContainerHighest: colors.surfaceRaised,
      outline: colors.outline,
      outlineVariant: colors.line,
    );
    final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_buttonRadius),
      ),
    );
    const buttonText = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    const buttonPadding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    const buttonSize = WidgetStatePropertyAll(Size(64, 32));
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_buttonRadius),
      borderSide: BorderSide(color: colors.outline),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
    );
    final textTheme = base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: text),
          bodySmall: TextStyle(fontSize: 12, height: 1.4, color: colors.muted),
          labelMedium: TextStyle(fontSize: 12, color: colors.muted),
          labelLarge: buttonText,
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: text,
          ),
          titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: colors.line,
      textTheme: textTheme,
      extensions: [colors],
      dividerTheme: DividerThemeData(color: colors.line, space: 1),
      iconTheme: IconThemeData(color: colors.muted, size: 16),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: buttonShape,
          textStyle: const WidgetStatePropertyAll(buttonText),
          padding: buttonPadding,
          minimumSize: buttonSize,
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return colors.line;
            if (s.contains(WidgetState.hovered) ||
                s.contains(WidgetState.pressed)) {
              return primaryHover;
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? colors.muted : onPrimary,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: buttonShape,
          textStyle: const WidgetStatePropertyAll(buttonText),
          padding: buttonPadding,
          minimumSize: buttonSize,
          foregroundColor: WidgetStatePropertyAll(colors.primaryText),
          side: WidgetStatePropertyAll(BorderSide(color: colors.outline)),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: .08)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: buttonShape,
          textStyle: const WidgetStatePropertyAll(buttonText),
          foregroundColor: WidgetStatePropertyAll(colors.primaryText),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        labelStyle: TextStyle(fontSize: 13, color: colors.muted),
        floatingLabelStyle: TextStyle(fontSize: 13, color: colors.muted),
        hintStyle: TextStyle(fontSize: 13, color: colors.muted),
        helperStyle: TextStyle(fontSize: 12, color: colors.muted),
        errorStyle: TextStyle(fontSize: 12, color: colors.danger),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_dialogRadius),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: .3),
      ),
    );
  }
}
