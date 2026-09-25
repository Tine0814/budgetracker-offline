import 'package:flutter/material.dart';

import '../models/domain_models.dart';
import '../theme/app_theme.dart';

const _genericAccountCardCanvas = Color(0xFF050D28);
const _genericAccountCardSurface = Color(0xFF12234B);

/// Broad institution groups used to organize the account-card picker.
///
/// The grouping is presentation metadata. It does not replace the institution
/// names or classifications published by the Bangko Sentral ng Pilipinas.
enum BankCardDesignGroup {
  generic,
  universalCommercial,
  thrift,
  digital,
  eWallet,
  ruralDigitalFirst,
}

extension BankCardDesignGroupLabel on BankCardDesignGroup {
  String get label => switch (this) {
    BankCardDesignGroup.generic => 'Generic / custom',
    BankCardDesignGroup.universalCommercial => 'Universal and commercial banks',
    BankCardDesignGroup.thrift => 'Thrift banks',
    BankCardDesignGroup.digital => 'Digital banks',
    BankCardDesignGroup.eWallet => 'E-wallets',
    BankCardDesignGroup.ruralDigitalFirst => 'Rural / digital-first banks',
  };
}

/// Original abstract motifs that the app may paint on an account card.
///
/// These describe geometry only. They are not bank logos, trademarks, or
/// reproductions of official card artwork.
enum BankCardPattern {
  auroraBands,
  contourWaves,
  diagonalFlow,
  facetedLight,
  horizonGlow,
  orbitRings,
  radialBurst,
  splitArc,
}

/// Immutable visual metadata for an account-card design.
///
/// Colors and patterns in this catalog are original Budget Flow treatments.
/// Institution names make the picker convenient, but the designs do not claim
/// to be official, exact, endorsed, or issued card artwork.
@immutable
class BankCardDesign {
  const BankCardDesign({
    required this.key,
    required this.name,
    required this.shortMark,
    required this.group,
    required this.pattern,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.foreground,
  });

  /// Stable value suitable for persistence.
  final String key;

  /// User-facing institution or generic design name.
  final String name;

  /// Text-only monogram rendered by the app; never an imported logo.
  final String shortMark;

  final BankCardDesignGroup group;
  final BankCardPattern pattern;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color foreground;
}

/// The resolved colors used to render a saved account's card design.
///
/// This deliberately mirrors the original Accounts treatment: catalog
/// designs use their exact saved colors, while Generic / custom designs blend
/// the account's saved color over the same dark card canvas. Keeping the
/// resolver here prevents dashboard variants from drifting from Accounts.
@immutable
class AccountCardVisual {
  const AccountCardVisual({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.foreground,
  });

  factory AccountCardVisual.fromDesign(BankCardDesign design) =>
      AccountCardVisual(
        primary: design.primary,
        secondary: design.secondary,
        accent: design.accent,
        foreground: design.foreground,
      );

  factory AccountCardVisual.forAccount(
    Account account,
    BankCardDesign design,
    AppPalette appPalette,
  ) {
    if (design.key != 'other') return AccountCardVisual.fromDesign(design);
    return AccountCardVisual.forCustomDesign(
      design,
      _savedAccountCardColor(
        account.color,
        fallback: appPalette.green,
        legacyReplacement: appPalette.greenDark,
      ),
    );
  }

  factory AccountCardVisual.forCustomDesign(
    BankCardDesign design,
    Color customColor,
  ) {
    if (design.key != 'other') return AccountCardVisual.fromDesign(design);
    return AccountCardVisual(
      primary: Color.lerp(_genericAccountCardCanvas, customColor, 0.24)!,
      secondary: Color.lerp(_genericAccountCardSurface, customColor, 0.42)!,
      accent: customColor,
      foreground: Colors.white,
    );
  }

  final Color primary;
  final Color secondary;
  final Color accent;
  final Color foreground;
}

Color _savedAccountCardColor(
  String value, {
  required Color fallback,
  required Color legacyReplacement,
}) {
  final normalized = value.replaceAll('#', '').toUpperCase();
  if (normalized == '159A73' ||
      normalized == '245C73' ||
      normalized == '18A57B' ||
      normalized == '000000' ||
      normalized == '1B1B1B' ||
      normalized == '111111' ||
      normalized == '181818') {
    return legacyReplacement;
  }
  final expanded = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.tryParse(expanded, radix: 16) ?? fallback.toARGB32());
}

/// Canonical short mark for Generic / custom account cards.
String accountCardShortMark(String type) => switch (type) {
  'credit_card' => 'CARD',
  'savings' => 'SAVE',
  'bank' => 'BANK',
  'ewallet' => 'WALLET',
  'cash' => 'CASH',
  _ => 'ACCT',
};

/// Canonical account type label shared by Accounts and dashboard cards.
String accountCardTypeLabel(String type) => switch (type) {
  'credit_card' => 'Credit card · liability',
  'savings' => 'Savings account · set aside',
  'bank' => 'Bank account',
  'ewallet' => 'E-wallet',
  'other' => 'Other account',
  _ => 'Cash account',
};

/// Paints the abstract motif assigned to a saved [BankCardDesign].
///
/// Keeping this painter beside the catalog ensures account cards, previews,
/// and compact dashboard treatments render the same pattern without copying
/// institution artwork or logos.
class BankCardPatternPainter extends CustomPainter {
  const BankCardPatternPainter({
    required this.pattern,
    required this.accent,
    required this.foreground,
  });

  final BankCardPattern pattern;
  final Color accent;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..color = foreground.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    switch (pattern) {
      case BankCardPattern.orbitRings:
        final center = Offset(size.width * 0.84, size.height * 0.26);
        for (final radius in [42.0, 72.0, 104.0]) {
          canvas.drawCircle(center, radius, soft);
        }
      case BankCardPattern.diagonalFlow:
        for (var x = -size.height; x < size.width; x += 38) {
          canvas.drawLine(
            Offset(x.toDouble(), size.height),
            Offset(x + size.height, 0),
            soft,
          );
        }
      case BankCardPattern.contourWaves:
        for (var i = 0; i < 4; i++) {
          final y = size.height * (0.55 + i * 0.1);
          final path = Path()
            ..moveTo(0, y)
            ..quadraticBezierTo(size.width * 0.36, y - 32, size.width * 0.68, y)
            ..quadraticBezierTo(size.width * 0.86, y + 22, size.width, y - 8);
          canvas.drawPath(path, soft);
        }
      case BankCardPattern.facetedLight:
        final path = Path()
          ..moveTo(size.width * 0.58, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.72)
          ..close();
        canvas.drawPath(path, glow);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height),
          Offset(size.width, size.height * 0.35),
          soft,
        );
      case BankCardPattern.horizonGlow:
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.76, size.height * 0.92),
            width: size.width * 0.8,
            height: size.height * 0.45,
          ),
          glow,
        );
        canvas.drawLine(
          Offset(0, size.height * 0.76),
          Offset(size.width, size.height * 0.76),
          soft,
        );
      case BankCardPattern.radialBurst:
        final center = Offset(size.width * 0.92, size.height * 0.16);
        for (var i = 0; i < 12; i++) {
          final angle = i * 0.5235987756;
          canvas.drawLine(
            center,
            center + Offset.fromDirection(angle, size.longestSide),
            soft,
          );
        }
      case BankCardPattern.splitArc:
        canvas.drawArc(
          Rect.fromLTWH(
            size.width * 0.52,
            -size.height * 0.28,
            size.width * 0.72,
            size.height * 1.2,
          ),
          1.2,
          3.8,
          false,
          soft..strokeWidth = 44,
        );
      case BankCardPattern.auroraBands:
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.85, size.height * 0.05),
            width: size.width * 0.72,
            height: size.height * 0.58,
          ),
          glow,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.08, size.height * 0.96),
            width: size.width * 0.58,
            height: size.height * 0.44,
          ),
          Paint()..color = foreground.withValues(alpha: 0.055),
        );
    }
  }

  @override
  bool shouldRepaint(covariant BankCardPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.accent != accent ||
      oldDelegate.foreground != foreground;
}

const genericBankCardDesign = BankCardDesign(
  key: 'other',
  name: 'Generic / custom',
  shortMark: 'BANK',
  group: BankCardDesignGroup.generic,
  pattern: BankCardPattern.auroraBands,
  primary: Color(0xFF142A55),
  secondary: Color(0xFF1D4F86),
  accent: Color(0xFF53C8E6),
  foreground: Colors.white,
);

const bdoBankCardDesign = BankCardDesign(
  key: 'bdo',
  name: 'BDO Unibank',
  shortMark: 'BDO',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.splitArc,
  primary: Color(0xFF173B71),
  secondary: Color(0xFF285D91),
  accent: Color(0xFFF0A94A),
  foreground: Colors.white,
);

const bpiBankCardDesign = BankCardDesign(
  key: 'bpi',
  name: 'Bank of the Philippine Islands',
  shortMark: 'BPI',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.contourWaves,
  primary: Color(0xFF681F35),
  secondary: Color(0xFF963C50),
  accent: Color(0xFFE8B765),
  foreground: Colors.white,
);

const metrobankBankCardDesign = BankCardDesign(
  key: 'metrobank',
  name: 'Metrobank',
  shortMark: 'MB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.orbitRings,
  primary: Color(0xFF173C69),
  secondary: Color(0xFF2D6596),
  accent: Color(0xFFE7B44A),
  foreground: Colors.white,
);

const unionBankCardDesign = BankCardDesign(
  key: 'unionbank',
  name: 'UnionBank of the Philippines',
  shortMark: 'UB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.diagonalFlow,
  primary: Color(0xFF653326),
  secondary: Color(0xFF9A4F2D),
  accent: Color(0xFFF0A251),
  foreground: Colors.white,
);

const rcbcBankCardDesign = BankCardDesign(
  key: 'rcbc',
  name: 'RCBC',
  shortMark: 'RCBC',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.facetedLight,
  primary: Color(0xFF123C78),
  secondary: Color(0xFF176FA3),
  accent: Color(0xFF57D4E8),
  foreground: Colors.white,
);

const securityBankCardDesign = BankCardDesign(
  key: 'security_bank',
  name: 'Security Bank',
  shortMark: 'SB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.horizonGlow,
  primary: Color(0xFF082C4C),
  secondary: Color(0xFF087D72),
  accent: Color(0xFF66D7C8),
  foreground: Colors.white,
);

const eastWestBankCardDesign = BankCardDesign(
  key: 'eastwest',
  name: 'EastWest Bank',
  shortMark: 'EW',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.radialBurst,
  primary: Color(0xFF4B376D),
  secondary: Color(0xFF76588F),
  accent: Color(0xFFE3B557),
  foreground: Colors.white,
);

const landbankBankCardDesign = BankCardDesign(
  key: 'landbank',
  name: 'LandBank',
  shortMark: 'LBP',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.contourWaves,
  primary: Color(0xFF205E4D),
  secondary: Color(0xFF368264),
  accent: Color(0xFFE0B951),
  foreground: Colors.white,
);

const pnbBankCardDesign = BankCardDesign(
  key: 'pnb',
  name: 'Philippine National Bank',
  shortMark: 'PNB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.splitArc,
  primary: Color(0xFF38527A),
  secondary: Color(0xFF5A7598),
  accent: Color(0xFFD9695F),
  foreground: Colors.white,
);

const chinaBankCardDesign = BankCardDesign(
  key: 'china_bank',
  name: 'China Bank',
  shortMark: 'CBC',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.facetedLight,
  primary: Color(0xFF72343D),
  secondary: Color(0xFFA25056),
  accent: Color(0xFFE3C26A),
  foreground: Colors.white,
);

const aubBankCardDesign = BankCardDesign(
  key: 'aub',
  name: 'Asia United Bank',
  shortMark: 'AUB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.horizonGlow,
  primary: Color(0xFF681C27),
  secondary: Color(0xFFA92E35),
  accent: Color(0xFFF1BE55),
  foreground: Colors.white,
);

const bankOfCommerceCardDesign = BankCardDesign(
  key: 'bank_of_commerce',
  name: 'Bank of Commerce',
  shortMark: 'BOC',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.orbitRings,
  primary: Color(0xFF102F5A),
  secondary: Color(0xFF1D548A),
  accent: Color(0xFFF2AC45),
  foreground: Colors.white,
);

const maybankCardDesign = BankCardDesign(
  key: 'maybank',
  name: 'Maybank Philippines',
  shortMark: 'MAY',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.diagonalFlow,
  primary: Color(0xFF49402D),
  secondary: Color(0xFF756643),
  accent: Color(0xFFF0C95D),
  foreground: Colors.white,
);

const pbcomBankCardDesign = BankCardDesign(
  key: 'pbcom',
  name: 'PBCom',
  shortMark: 'PBC',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.auroraBands,
  primary: Color(0xFF761F28),
  secondary: Color(0xFFC54431),
  accent: Color(0xFFF29A4B),
  foreground: Colors.white,
);

const ctbcBankCardDesign = BankCardDesign(
  key: 'ctbc',
  name: 'CTBC Bank Philippines',
  shortMark: 'CTBC',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.radialBurst,
  primary: Color(0xFF3E5264),
  secondary: Color(0xFF647A8B),
  accent: Color(0xFFD55C62),
  foreground: Colors.white,
);

const cimbBankCardDesign = BankCardDesign(
  key: 'cimb',
  name: 'CIMB Bank Philippines',
  shortMark: 'CIMB',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.splitArc,
  primary: Color(0xFF661821),
  secondary: Color(0xFFB22532),
  accent: Color(0xFFF27A7E),
  foreground: Colors.white,
);

const dbpBankCardDesign = BankCardDesign(
  key: 'dbp',
  name: 'Development Bank of the Philippines',
  shortMark: 'DBP',
  group: BankCardDesignGroup.universalCommercial,
  pattern: BankCardPattern.horizonGlow,
  primary: Color(0xFF153C73),
  secondary: Color(0xFF2869A0),
  accent: Color(0xFFE45E5E),
  foreground: Colors.white,
);

const psbankCardDesign = BankCardDesign(
  key: 'psbank',
  name: 'PSBank',
  shortMark: 'PSB',
  group: BankCardDesignGroup.thrift,
  pattern: BankCardPattern.contourWaves,
  primary: Color(0xFF314F76),
  secondary: Color(0xFF53759A),
  accent: Color(0xFF75C1D2),
  foreground: Colors.white,
);

const goTymeBankCardDesign = BankCardDesign(
  key: 'gotyme',
  name: 'GoTyme Bank',
  shortMark: 'GT',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.auroraBands,
  primary: Color(0xFF0B2029),
  secondary: Color(0xFF15556A),
  accent: Color(0xFF72E5DF),
  foreground: Colors.white,
);

const mayaBankCardDesign = BankCardDesign(
  key: 'maya',
  name: 'Maya Bank',
  shortMark: 'MAYA',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.radialBurst,
  primary: Color(0xFF0A211C),
  secondary: Color(0xFF075A43),
  accent: Color(0xFF54E59B),
  foreground: Colors.white,
);

const tonikBankCardDesign = BankCardDesign(
  key: 'tonik',
  name: 'Tonik Digital Bank',
  shortMark: 'TONIK',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.orbitRings,
  primary: Color(0xFF4A204C),
  secondary: Color(0xFF8C2F70),
  accent: Color(0xFFF2A1CC),
  foreground: Colors.white,
);

const unionDigitalCardDesign = BankCardDesign(
  key: 'union_digital',
  name: 'UnionDigital Bank',
  shortMark: 'UD',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.diagonalFlow,
  primary: Color(0xFF3E285F),
  secondary: Color(0xFF704487),
  accent: Color(0xFFF09A45),
  foreground: Colors.white,
);

const unoBankCardDesign = BankCardDesign(
  key: 'uno',
  name: 'UNO Digital Bank',
  shortMark: 'UNO',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.facetedLight,
  primary: Color(0xFF3D3F72),
  secondary: Color(0xFF6264A0),
  accent: Color(0xFF68C8D1),
  foreground: Colors.white,
);

const ofBankCardDesign = BankCardDesign(
  key: 'ofbank',
  name: 'Overseas Filipino Bank',
  shortMark: 'OFB',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.horizonGlow,
  primary: Color(0xFF173A70),
  secondary: Color(0xFF2A67A0),
  accent: Color(0xFFE5BB4F),
  foreground: Colors.white,
);

const mariBankCardDesign = BankCardDesign(
  key: 'maribank',
  name: 'MariBank Philippines',
  shortMark: 'MARI',
  group: BankCardDesignGroup.digital,
  pattern: BankCardPattern.contourWaves,
  primary: Color(0xFF8A4933),
  secondary: Color(0xFFB96A45),
  accent: Color(0xFFF3BC67),
  foreground: Colors.white,
);

const gcashCardDesign = BankCardDesign(
  key: 'gcash',
  name: 'GCash',
  shortMark: 'GCASH',
  group: BankCardDesignGroup.eWallet,
  pattern: BankCardPattern.orbitRings,
  primary: Color(0xFF073B89),
  secondary: Color(0xFF0876E8),
  accent: Color(0xFF53D6FF),
  foreground: Colors.white,
);

const ownBankCardDesign = BankCardDesign(
  key: 'ownbank',
  name: 'OwnBank',
  shortMark: 'OWN',
  group: BankCardDesignGroup.ruralDigitalFirst,
  pattern: BankCardPattern.splitArc,
  primary: Color(0xFF304E66),
  secondary: Color(0xFF4F7488),
  accent: Color(0xFF8DD0CA),
  foreground: Colors.white,
);

const netbankCardDesign = BankCardDesign(
  key: 'netbank',
  name: 'Netbank',
  shortMark: 'NET',
  group: BankCardDesignGroup.ruralDigitalFirst,
  pattern: BankCardPattern.auroraBands,
  primary: Color(0xFF275967),
  secondary: Color(0xFF3F8190),
  accent: Color(0xFF8BD3C2),
  foreground: Colors.white,
);

const List<BankCardDesign> genericBankCardDesigns = [genericBankCardDesign];

const List<BankCardDesign> universalCommercialBankCardDesigns = [
  bdoBankCardDesign,
  bpiBankCardDesign,
  metrobankBankCardDesign,
  unionBankCardDesign,
  rcbcBankCardDesign,
  securityBankCardDesign,
  eastWestBankCardDesign,
  landbankBankCardDesign,
  pnbBankCardDesign,
  chinaBankCardDesign,
  aubBankCardDesign,
  bankOfCommerceCardDesign,
  maybankCardDesign,
  pbcomBankCardDesign,
  ctbcBankCardDesign,
  cimbBankCardDesign,
  dbpBankCardDesign,
];

const List<BankCardDesign> thriftBankCardDesigns = [psbankCardDesign];

const List<BankCardDesign> digitalBankCardDesigns = [
  goTymeBankCardDesign,
  mayaBankCardDesign,
  tonikBankCardDesign,
  unionDigitalCardDesign,
  unoBankCardDesign,
  ofBankCardDesign,
  mariBankCardDesign,
];

const List<BankCardDesign> eWalletCardDesigns = [gcashCardDesign];

const List<BankCardDesign> ruralDigitalFirstBankCardDesigns = [
  ownBankCardDesign,
  netbankCardDesign,
];

/// Picker-ready designs ordered by their display groups.
const List<BankCardDesign> philippineBankCardDesigns = [
  ...genericBankCardDesigns,
  ...universalCommercialBankCardDesigns,
  ...thriftBankCardDesigns,
  ...digitalBankCardDesigns,
  ...eWalletCardDesigns,
  ...ruralDigitalFirstBankCardDesigns,
];

/// Picker-ready designs separated into labeled sections.
const Map<BankCardDesignGroup, List<BankCardDesign>> bankCardDesignsByGroup = {
  BankCardDesignGroup.generic: genericBankCardDesigns,
  BankCardDesignGroup.universalCommercial: universalCommercialBankCardDesigns,
  BankCardDesignGroup.thrift: thriftBankCardDesigns,
  BankCardDesignGroup.digital: digitalBankCardDesigns,
  BankCardDesignGroup.eWallet: eWalletCardDesigns,
  BankCardDesignGroup.ruralDigitalFirst: ruralDigitalFirstBankCardDesigns,
};

const Map<String, BankCardDesign> _bankCardDesignLookup = {
  'other': genericBankCardDesign,
  'generic': genericBankCardDesign,
  'custom': genericBankCardDesign,
  'bdo': bdoBankCardDesign,
  'bdounibank': bdoBankCardDesign,
  'bpi': bpiBankCardDesign,
  'bankofthephilippineislands': bpiBankCardDesign,
  'metrobank': metrobankBankCardDesign,
  'metropolitanbankandtrustcompany': metrobankBankCardDesign,
  'unionbank': unionBankCardDesign,
  'unionbankofthephilippines': unionBankCardDesign,
  'ub': unionBankCardDesign,
  'rcbc': rcbcBankCardDesign,
  'rizalcommercialbankingcorporation': rcbcBankCardDesign,
  'securitybank': securityBankCardDesign,
  'eastwest': eastWestBankCardDesign,
  'eastwestbank': eastWestBankCardDesign,
  'landbank': landbankBankCardDesign,
  'landbankofthephilippines': landbankBankCardDesign,
  'lbp': landbankBankCardDesign,
  'pnb': pnbBankCardDesign,
  'philippinenationalbank': pnbBankCardDesign,
  'chinabank': chinaBankCardDesign,
  'chinabankingcorporation': chinaBankCardDesign,
  'cbc': chinaBankCardDesign,
  'aub': aubBankCardDesign,
  'asiaunitedbank': aubBankCardDesign,
  'bankofcommerce': bankOfCommerceCardDesign,
  'boc': bankOfCommerceCardDesign,
  'maybank': maybankCardDesign,
  'maybankphilippines': maybankCardDesign,
  'pbcom': pbcomBankCardDesign,
  'philippinebankofcommunications': pbcomBankCardDesign,
  'ctbc': ctbcBankCardDesign,
  'ctbcbankphilippines': ctbcBankCardDesign,
  'cimb': cimbBankCardDesign,
  'cimbbankphilippines': cimbBankCardDesign,
  'dbp': dbpBankCardDesign,
  'developmentbankofthephilippines': dbpBankCardDesign,
  'psbank': psbankCardDesign,
  'philippinesavingsbank': psbankCardDesign,
  'gotyme': goTymeBankCardDesign,
  'gotymebank': goTymeBankCardDesign,
  'maya': mayaBankCardDesign,
  'mayabank': mayaBankCardDesign,
  'tonik': tonikBankCardDesign,
  'tonikdigitalbank': tonikBankCardDesign,
  'uniondigital': unionDigitalCardDesign,
  'uniondigitalbank': unionDigitalCardDesign,
  'uno': unoBankCardDesign,
  'unobank': unoBankCardDesign,
  'unodigitalbank': unoBankCardDesign,
  'ofbank': ofBankCardDesign,
  'overseasfilipinobank': ofBankCardDesign,
  'maribank': mariBankCardDesign,
  'maribankphilippines': mariBankCardDesign,
  'seabank': mariBankCardDesign,
  'gcash': gcashCardDesign,
  'gxchange': gcashCardDesign,
  'gxi': gcashCardDesign,
  'ownbank': ownBankCardDesign,
  'netbank': netbankCardDesign,
};

/// Resolves a saved key, short mark, or common institution name.
///
/// Unknown and blank values intentionally use the generic design so account
/// data remains renderable when the catalog grows or an institution is renamed.
BankCardDesign bankCardDesignFor(String? value) {
  if (value == null || value.trim().isEmpty) return genericBankCardDesign;
  final normalized = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return _bankCardDesignLookup[normalized] ?? genericBankCardDesign;
}
