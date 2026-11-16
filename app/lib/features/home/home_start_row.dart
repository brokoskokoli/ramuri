import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Knopfzeile auf „Heute“ mit offener Einheit (Design `Main.dc.html`):
/// [primary] („Einheit starten“) nimmt den Rest der Zeile, [secondary]
/// („Frei laufen“) nur seine eigene Breite, dazwischen [gap].
///
/// Passen beide nicht mit ihrer natürlichen Breite (größte intrinsische
/// Breite, also einzeilig) nebeneinander – große Schrift, schmales Display –,
/// stehen sie in voller Breite untereinander, [primary] oben, statt dass ein
/// Text umbricht oder abgeschnitten wird.
class HomeStartRow extends StatelessWidget {
  const HomeStartRow({
    super.key,
    required this.primary,
    required this.secondary,
    this.gap = 10,
  });

  final Widget primary;
  final Widget secondary;
  final double gap;

  /// Innenabstand von „Frei laufen“ wie im Design (`padding: 0 18px`).
  static const secondaryPadding = EdgeInsets.symmetric(horizontal: 18);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // „Einheit starten“ ist im Design ohne Innenabstand gesetzt und zentriert
    // Symbol und Text in der Restbreite; so passt die Zeile auch bei 360 dp.
    final filled = theme.filledButtonTheme.style ?? const ButtonStyle();
    final outlined = theme.outlinedButtonTheme.style ?? const ButtonStyle();
    return _HomeStartRowLayout(
      gap: gap,
      children: [
        Theme(
          data: theme.copyWith(
            filledButtonTheme: FilledButtonThemeData(
              style: filled.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
            ),
          ),
          child: primary,
        ),
        Theme(
          data: theme.copyWith(
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: outlined.copyWith(
                padding: const WidgetStatePropertyAll(secondaryPadding),
              ),
            ),
          ),
          child: secondary,
        ),
      ],
    );
  }
}

class _HomeStartRowLayout extends MultiChildRenderObjectWidget {
  const _HomeStartRowLayout({required this.gap, required super.children});

  final double gap;

  @override
  RenderHomeStartRow createRenderObject(BuildContext context) =>
      RenderHomeStartRow(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHomeStartRow renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _SlotData extends ContainerBoxParentData<RenderBox> {}

/// Render-Objekt zu [HomeStartRow]; [stacked] meldet, ob die Knöpfe
/// untereinander stehen.
class RenderHomeStartRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  RenderHomeStartRow(this._gap);

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  bool _stacked = false;
  bool get stacked => _stacked;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  RenderBox get _primary => firstChild!;
  RenderBox get _secondary => lastChild!;

  bool _fitsSideBySide(double maxWidth) {
    final need =
        _primary.getMaxIntrinsicWidth(double.infinity) +
        _gap +
        _secondary.getMaxIntrinsicWidth(double.infinity);
    return need <= maxWidth;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _primary.getMaxIntrinsicWidth(double.infinity),
    _secondary.getMaxIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _primary.getMaxIntrinsicWidth(double.infinity) +
      _gap +
      _secondary.getMaxIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicHeight(double width) => _layout(
    BoxConstraints.tightFor(width: width),
    (child, c) => child.getDryLayout(c),
  ).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, (child, c) => child.getDryLayout(c));

  @override
  void performLayout() {
    size = _layout(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    }, place: true);
  }

  Size _layout(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints c) layoutChild, {
    bool place = false,
  }) {
    final width = constraints.maxWidth;
    final side = width.isFinite && _fitsSideBySide(width);
    if (place) _stacked = !side;
    if (side) {
      final sW = _secondary.getMaxIntrinsicWidth(double.infinity);
      final s = layoutChild(_secondary, BoxConstraints.tightFor(width: sW));
      final p = layoutChild(
        _primary,
        BoxConstraints.tightFor(width: width - _gap - sW),
      );
      final h = math.max(p.height, s.height);
      if (place) {
        (_primary.parentData! as _SlotData).offset = Offset(
          0,
          (h - p.height) / 2,
        );
        (_secondary.parentData! as _SlotData).offset = Offset(
          width - sW,
          (h - s.height) / 2,
        );
      }
      return constraints.constrain(Size(width, h));
    }
    final full = width.isFinite
        ? BoxConstraints.tightFor(width: width)
        : const BoxConstraints();
    final p = layoutChild(_primary, full);
    final s = layoutChild(_secondary, full);
    if (place) {
      (_primary.parentData! as _SlotData).offset = Offset.zero;
      (_secondary.parentData! as _SlotData).offset = Offset(0, p.height + _gap);
    }
    return constraints.constrain(
      Size(math.max(p.width, s.width), p.height + _gap + s.height),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
