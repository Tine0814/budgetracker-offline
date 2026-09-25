import 'package:flutter/material.dart';

/// Shared palette for the Arcadia-inspired interface.
///
/// The legacy green-named colors remain as aliases because the feature screens
/// use them semantically: [greenDark] is the primary action color and [green]
/// is the positive/income color.
abstract final class AppColors {
  static const ink = Color(0xFFF4F7FF);
  static const inkSoft = Color(0xFFBAC6E2);
  static const canvas = Color(0xFF050D28);
  static const surface = Color(0xFF0E1A3D);
  static const surfaceRaised = Color(0xFF12234B);
  static const surfaceMuted = Color(0xFF091532);
  static const input = Color(0xFF0A1737);

  static const green = Color(0xFF43D98B);
  static const greenDark = Color(0xFF6F92FF);
  static const mint = Color(0xFF172E64);
  static const success = Color(0xFF43D98B);
  static const successSoft = Color(0xFF10383A);

  static const orange = Color(0xFFFFA13D);
  static const orangeSoft = Color(0xFF38243A);
  static const red = Color(0xFFFF607B);
  static const redSoft = Color(0xFF3B1C36);
  static const violet = Color(0xFFC74AF3);
  static const violetSoft = Color(0xFF34205A);
  static const cyan = Color(0xFF55D7E8);
  static const infoSoft = Color(0xFF152C5E);
  static const gold = Color(0xFFF2BE58);
  static const goldSoft = Color(0xFF352C32);

  static const border = Color(0xFF20345F);
  static const borderStrong = Color(0xFF526FA5);
  static const muted = Color(0xFF8290B1);
  static const sidebar = Color(0xFF0A1533);
  static const sidebarSelected = Color(0xFF172D62);
  static const sidebarFooter = Color(0xFF101F43);

  static const gradientStart = Color(0xFF3F5AB5);
  static const gradientEnd = Color(0xFF8252D3);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.inkSoft,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.input,
    required this.green,
    required this.greenDark,
    required this.mint,
    required this.success,
    required this.successSoft,
    required this.orange,
    required this.orangeSoft,
    required this.red,
    required this.redSoft,
    required this.violet,
    required this.violetSoft,
    required this.cyan,
    required this.infoSoft,
    required this.gold,
    required this.goldSoft,
    required this.border,
    required this.borderStrong,
    required this.muted,
    required this.sidebar,
    required this.sidebarSelected,
    required this.sidebarFooter,
    required this.onSidebar,
    required this.onSidebarMuted,
    required this.sidebarBorder,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.onHeroMuted,
    required this.gradientStart,
    required this.gradientEnd,
    required this.onPrimary,
  });

  static const dark = AppPalette(
    ink: AppColors.ink,
    inkSoft: AppColors.inkSoft,
    canvas: AppColors.canvas,
    surface: AppColors.surface,
    surfaceRaised: AppColors.surfaceRaised,
    surfaceMuted: AppColors.surfaceMuted,
    input: AppColors.input,
    green: AppColors.green,
    greenDark: AppColors.greenDark,
    mint: AppColors.mint,
    success: AppColors.success,
    successSoft: AppColors.successSoft,
    orange: AppColors.orange,
    orangeSoft: AppColors.orangeSoft,
    red: AppColors.red,
    redSoft: AppColors.redSoft,
    violet: AppColors.violet,
    violetSoft: AppColors.violetSoft,
    cyan: AppColors.cyan,
    infoSoft: AppColors.infoSoft,
    gold: AppColors.gold,
    goldSoft: AppColors.goldSoft,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    muted: AppColors.muted,
    sidebar: AppColors.sidebar,
    sidebarSelected: AppColors.sidebarSelected,
    sidebarFooter: AppColors.sidebarFooter,
    onSidebar: AppColors.ink,
    onSidebarMuted: AppColors.inkSoft,
    sidebarBorder: AppColors.border,
    heroStart: AppColors.surfaceRaised,
    heroEnd: Color(0xFF203C7A),
    onHero: Colors.white,
    onHeroMuted: AppColors.inkSoft,
    gradientStart: AppColors.gradientStart,
    gradientEnd: AppColors.gradientEnd,
    onPrimary: AppColors.canvas,
  );

  static const light = AppPalette(
    ink: Color(0xFF12213A),
    inkSoft: Color(0xFF40516D),
    canvas: Color(0xFFF4F7FC),
    surface: Colors.white,
    surfaceRaised: Color(0xFFF8FAFF),
    surfaceMuted: Color(0xFFEDF2FA),
    input: Color(0xFFF8FAFF),
    green: Color(0xFF087A4C),
    greenDark: Color(0xFF3158C8),
    mint: Color(0xFFE4EBFF),
    success: Color(0xFF087A4C),
    successSoft: Color(0xFFE8F7EF),
    orange: Color(0xFFA45100),
    orangeSoft: Color(0xFFFFF0DF),
    red: Color(0xFFC33A53),
    redSoft: Color(0xFFFDEBF0),
    violet: Color(0xFF7A36B5),
    violetSoft: Color(0xFFF4EAFB),
    cyan: Color(0xFF007388),
    infoSoft: Color(0xFFE8F2FF),
    gold: Color(0xFF8A6113),
    goldSoft: Color(0xFFFFF5DC),
    border: Color(0xFFD9E2F0),
    borderStrong: Color(0xFF71839F),
    muted: Color(0xFF5A6982),
    sidebar: Color(0xFF0A1533),
    sidebarSelected: Color(0xFF172D62),
    sidebarFooter: Color(0xFF101F43),
    onSidebar: Color(0xFFF4F7FF),
    onSidebarMuted: Color(0xFFBAC6E2),
    sidebarBorder: Color(0xFF20345F),
    heroStart: Color(0xFF12234B),
    heroEnd: Color(0xFF203C7A),
    onHero: Colors.white,
    onHeroMuted: Color(0xFFBAC6E2),
    gradientStart: Color(0xFF3158C8),
    gradientEnd: Color(0xFF6A49B8),
    onPrimary: Colors.white,
  );

  final Color ink;
  final Color inkSoft;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color input;
  final Color green;
  final Color greenDark;
  final Color mint;
  final Color success;
  final Color successSoft;
  final Color orange;
  final Color orangeSoft;
  final Color red;
  final Color redSoft;
  final Color violet;
  final Color violetSoft;
  final Color cyan;
  final Color infoSoft;
  final Color gold;
  final Color goldSoft;
  final Color border;
  final Color borderStrong;
  final Color muted;
  final Color sidebar;
  final Color sidebarSelected;
  final Color sidebarFooter;
  final Color onSidebar;
  final Color onSidebarMuted;
  final Color sidebarBorder;
  final Color heroStart;
  final Color heroEnd;
  final Color onHero;
  final Color onHeroMuted;
  final Color gradientStart;
  final Color gradientEnd;
  final Color onPrimary;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color blend(Color start, Color end) => Color.lerp(start, end, t)!;
    return AppPalette(
      ink: blend(ink, other.ink),
      inkSoft: blend(inkSoft, other.inkSoft),
      canvas: blend(canvas, other.canvas),
      surface: blend(surface, other.surface),
      surfaceRaised: blend(surfaceRaised, other.surfaceRaised),
      surfaceMuted: blend(surfaceMuted, other.surfaceMuted),
      input: blend(input, other.input),
      green: blend(green, other.green),
      greenDark: blend(greenDark, other.greenDark),
      mint: blend(mint, other.mint),
      success: blend(success, other.success),
      successSoft: blend(successSoft, other.successSoft),
      orange: blend(orange, other.orange),
      orangeSoft: blend(orangeSoft, other.orangeSoft),
      red: blend(red, other.red),
      redSoft: blend(redSoft, other.redSoft),
      violet: blend(violet, other.violet),
      violetSoft: blend(violetSoft, other.violetSoft),
      cyan: blend(cyan, other.cyan),
      infoSoft: blend(infoSoft, other.infoSoft),
      gold: blend(gold, other.gold),
      goldSoft: blend(goldSoft, other.goldSoft),
      border: blend(border, other.border),
      borderStrong: blend(borderStrong, other.borderStrong),
      muted: blend(muted, other.muted),
      sidebar: blend(sidebar, other.sidebar),
      sidebarSelected: blend(sidebarSelected, other.sidebarSelected),
      sidebarFooter: blend(sidebarFooter, other.sidebarFooter),
      onSidebar: blend(onSidebar, other.onSidebar),
      onSidebarMuted: blend(onSidebarMuted, other.onSidebarMuted),
      sidebarBorder: blend(sidebarBorder, other.sidebarBorder),
      heroStart: blend(heroStart, other.heroStart),
      heroEnd: blend(heroEnd, other.heroEnd),
      onHero: blend(onHero, other.onHero),
      onHeroMuted: blend(onHeroMuted, other.onHeroMuted),
      gradientStart: blend(gradientStart, other.gradientStart),
      gradientEnd: blend(gradientEnd, other.gradientEnd),
      onPrimary: blend(onPrimary, other.onPrimary),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.light
          ? AppPalette.light
          : AppPalette.dark);
}

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData get light => _build(Brightness.light, AppPalette.light);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.greenDark,
      onPrimary: palette.onPrimary,
      secondary: palette.violet,
      onSecondary: palette.onPrimary,
      tertiary: palette.cyan,
      onTertiary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.ink,
      error: palette.red,
      onError: palette.onPrimary,
      outline: palette.border,
      outlineVariant: palette.border,
    );

    final textTheme = TextTheme(
      displaySmall: TextStyle(
        color: palette.ink,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.12,
      ),
      headlineSmall: TextStyle(
        color: palette.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleLarge: TextStyle(
        color: palette.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: palette.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: palette.inkSoft, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: palette.inkSoft, fontSize: 14, height: 1.4),
      bodySmall: TextStyle(color: palette.muted, fontSize: 12, height: 1.35),
      labelLarge: TextStyle(
        color: palette.ink,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      labelMedium: TextStyle(
        color: palette.inkSoft,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );

    final roundedInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: palette.borderStrong),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      disabledColor: palette.muted.withValues(alpha: 0.45),
      shadowColor: Colors.black.withValues(alpha: 0.32),
      splashColor: palette.greenDark.withValues(alpha: 0.10),
      highlightColor: palette.greenDark.withValues(alpha: 0.07),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: palette.inkSoft),
      primaryIconTheme: IconThemeData(color: palette.ink),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: palette.canvas,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: palette.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.input,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: palette.muted),
        hintStyle: TextStyle(color: palette.muted.withValues(alpha: 0.72)),
        helperStyle: TextStyle(color: palette.muted),
        errorStyle: TextStyle(color: palette.red),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
        border: roundedInputBorder,
        enabledBorder: roundedInputBorder,
        disabledBorder: roundedInputBorder.copyWith(
          borderSide: BorderSide(color: palette.border.withValues(alpha: 0.55)),
        ),
        focusedBorder: roundedInputBorder.copyWith(
          borderSide: BorderSide(color: palette.greenDark, width: 1.5),
        ),
        errorBorder: roundedInputBorder.copyWith(
          borderSide: BorderSide(color: palette.red),
        ),
        focusedErrorBorder: roundedInputBorder.copyWith(
          borderSide: BorderSide(color: palette.red, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.greenDark,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.surfaceRaised,
          disabledForegroundColor: palette.muted,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.borderStrong),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.greenDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.inkSoft,
          highlightColor: palette.mint,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return palette.mint;
            return palette.surfaceMuted;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return palette.ink;
            if (states.contains(WidgetState.disabled)) return palette.muted;
            return palette.inkSoft;
          }),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? palette.greenDark
                  : palette.border,
            ),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          overlayColor: WidgetStateProperty.all(
            palette.greenDark.withValues(alpha: 0.08),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: palette.border,
        indicatorColor: palette.greenDark,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: palette.ink,
        unselectedLabelColor: palette.muted,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(palette.surfaceMuted),
        dataRowColor: WidgetStatePropertyAll(palette.surface),
        headingTextStyle: TextStyle(
          color: palette.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.55,
        ),
        dataTextStyle: TextStyle(color: palette.inkSoft, fontSize: 13),
        dividerThickness: 1,
        headingRowHeight: 48,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 68,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(BorderSide(color: palette.border)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: palette.sidebar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.sidebarSelected,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.onSidebar
                : palette.onSidebarMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.onSidebar
                : palette.onSidebarMuted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: palette.sidebar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.sidebarSelected,
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: palette.onSidebarMuted),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: palette.onSidebarMuted, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 20,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: palette.border),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: palette.surfaceRaised,
        headerForegroundColor: palette.ink,
        dividerColor: palette.border,
        todayForegroundColor: WidgetStatePropertyAll(palette.greenDark),
        todayBorder: BorderSide(color: palette.greenDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: palette.border),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: palette.surface,
        dialBackgroundColor: palette.surfaceMuted,
        dialHandColor: palette.greenDark,
        hourMinuteColor: palette.surfaceRaised,
        hourMinuteTextColor: palette.ink,
        dayPeriodColor: palette.surfaceRaised,
        dayPeriodTextColor: palette.inkSoft,
        entryModeIconColor: palette.greenDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          side: BorderSide(color: palette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: palette.inkSoft),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: palette.border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.surfaceRaised),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.greenDark
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(palette.onPrimary),
        side: BorderSide(color: palette.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.greenDark
              : palette.muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.greenDark
              : palette.surfaceRaised,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.border),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceMuted,
        selectedColor: palette.mint,
        disabledColor: palette.surfaceMuted,
        side: BorderSide(color: palette.border),
        labelStyle: TextStyle(color: palette.inkSoft),
        secondaryLabelStyle: TextStyle(color: palette.ink),
        shape: StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(color: palette.ink),
        actionTextColor: palette.greenDark,
        behavior: SnackBarBehavior.floating,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: palette.borderStrong),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.greenDark,
        linearTrackColor: palette.surfaceRaised,
        circularTrackColor: palette.surfaceRaised,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.greenDark,
        inactiveTrackColor: palette.border,
        thumbColor: palette.greenDark,
        overlayColor: palette.mint,
        valueIndicatorColor: palette.surfaceRaised,
        valueIndicatorTextStyle: TextStyle(color: palette.ink),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: palette.violet,
        textColor: palette.onPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      dividerColor: palette.border,
      listTileTheme: ListTileThemeData(
        iconColor: palette.inkSoft,
        textColor: palette.ink,
        subtitleTextStyle: TextStyle(color: palette.muted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.borderStrong),
        ),
        textStyle: TextStyle(color: palette.ink, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          palette.borderStrong.withValues(alpha: 0.9),
        ),
        trackColor: WidgetStatePropertyAll(Colors.transparent),
        radius: Radius.circular(999),
      ),
    );
  }
}
