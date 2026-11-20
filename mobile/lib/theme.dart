import 'package:flutter/material.dart';

/// Shopping-app inspired palette: navy, orange, yellow buttons, teal header.
class AppColors {
  static const navy = Color(0xFF131921);
  static const navy2 = Color(0xFF232F3E);
  static const navy3 = Color(0xFF37475A);
  static const page = Color(0xFFEAEDED);
  static const card = Colors.white;
  static const text = Color(0xFF0F1111);
  static const muted = Color(0xFF565959);
  static const link = Color(0xFF007185);
  static const orange = Color(0xFFFF9900);
  static const yellow = Color(0xFFFFD814);
  static const yellowBorder = Color(0xFFFCD200);
  static const orangeButton = Color(0xFFFFA41C);
  static const orangeBorder = Color(0xFFFF8F00);
  static const green = Color(0xFF067D62);
  static const red = Color(0xFFB12704);
  static const star = Color(0xFFDE7921);
  static const border = Color(0xFFD5D9D9);
  static const headerTop = Color(0xFF84D8E3);
  static const headerBottom = Color(0xFFA6E6CE);
  static const locationStrip = Color(0xFFC9EADF);
  static const tabSelected = Color(0xFF008296);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.orange,
      primary: AppColors.navy2,
      secondary: AppColors.orange,
      surface: AppColors.card,
    ),
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.orange),
  );
}

/// Rounded "add to cart" style button.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.orange = false,
    this.white = false,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool orange;
  final bool white;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bg = white ? Colors.white : (orange ? AppColors.orangeButton : AppColors.yellow);
    final border = white ? AppColors.border : (orange ? AppColors.orangeBorder : AppColors.yellowBorder);
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: AppColors.text,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        disabledForegroundColor: AppColors.text.withValues(alpha: 0.5),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 13),
        minimumSize: Size(0, dense ? 36 : 44),
        shape: StadiumBorder(side: BorderSide(color: border)),
        textStyle: TextStyle(fontSize: dense ? 13 : 15, fontWeight: FontWeight.w500),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.size = 16});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final icon = value >= i + 1
            ? Icons.star_rounded
            : (value > i ? Icons.star_half_rounded : Icons.star_outline_rounded);
        return Icon(icon, size: size, color: AppColors.star);
      }),
    );
  }
}
