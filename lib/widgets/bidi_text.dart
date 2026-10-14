import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// Direction of [text] on its own, e.g. a Latin channel name in an Arabic UI.
TextDirection textDirectionFor(String text) =>
    Bidi.detectRtlDirectionality(text) ? TextDirection.rtl : TextDirection.ltr;

/// Single-style text laid out in its own direction ([textDirectionFor]) but
/// aligned to the ambient start edge, so mixed Arabic/Latin lists line up.
class BidiText extends StatelessWidget {
  const BidiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  /// Defaults to the ambient start edge.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final ambient = Directionality.of(context);
    final align =
        textAlign ??
        (ambient == TextDirection.rtl ? TextAlign.right : TextAlign.left);
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: maxLines != 1,
      textAlign: align,
      textDirection: textDirectionFor(text),
    );
  }
}
