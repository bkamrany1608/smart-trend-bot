import 'package:flutter/material.dart';
import '../core/models.dart';

const kCard = Color(0xFF16212E);
const kGreen = Color(0xFF00E676);
const kRed = Color(0xFFFF5252);
const kOrange = Color(0xFFFFA726);

Color regimeColor(Regime r) => r == Regime.up ? kGreen : (r == Regime.down ? kRed : kOrange);
String regimeLabel(Regime r) => switch (r) {
      Regime.up => 'صعودی',
      Regime.down => 'نزولی',
      Regime.range => 'رنج',
      Regime.volatile => 'نوسان شدید',
    };

String fmtP(double x) => x.abs() >= 100 ? x.toStringAsFixed(2) : (x.abs() >= 1 ? x.toStringAsFixed(4) : x.toStringAsFixed(6));
String fmtM(double x) => (x >= 0 ? '+' : '') + x.toStringAsFixed(2);
String fmtT(int t) => DateTime.fromMillisecondsSinceEpoch(t).toString().substring(5, 16);

Widget card(Widget child, {EdgeInsets? margin}) => Card(
      color: kCard,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );

Widget kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        Flexible(child: Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );

/// Floating trend-strength bar: green = up, red = down, orange = range / violent.
class TrendBar extends StatelessWidget {
  final RegimeInfo? r;
  const TrendBar(this.r, {super.key});
  @override
  Widget build(BuildContext context) {
    final info = r;
    if (info == null) return const Text('برای نمایش روند، اسکن را اجرا کنید', style: TextStyle(color: Colors.white54));
    final col = regimeColor(info.regime);
    final f = (info.strength / 100).clamp(0.02, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(info.regime == Regime.up ? Icons.trending_up : info.regime == Regime.down ? Icons.trending_down : Icons.warning_amber_rounded, color: col),
        const SizedBox(width: 8),
        Text('${regimeLabel(info.regime)}  ${info.strength.toStringAsFixed(0)}%', style: TextStyle(color: col, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(info.note, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (c, cs) {
        final w = cs.maxWidth;
        return SizedBox(
          height: 22,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 10, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 10, width: w * f,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: [col.withOpacity(0.35), col])),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              left: (w * f - 11).clamp(0.0, w - 22),
              child: Container(width: 22, height: 22, decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
            ),
          ]),
        );
      }),
    ]);
  }
}

class NumTile extends StatefulWidget {
  final String label, initial;
  final void Function(String) onSaved;
  final bool text, obscure;
  const NumTile(this.label, this.initial, this.onSaved, {super.key, this.text = false, this.obscure = false});
  @override
  State<NumTile> createState() => _NumTileState();
}

class _NumTileState extends State<NumTile> {
  late final TextEditingController c = TextEditingController(text: widget.initial);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          obscureText: widget.obscure,
          textDirection: TextDirection.ltr,
          keyboardType: widget.text ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()),
          onSubmitted: widget.onSaved,
          onEditingComplete: () {
            widget.onSaved(c.text);
            FocusScope.of(context).unfocus();
          },
        ),
      );
}
