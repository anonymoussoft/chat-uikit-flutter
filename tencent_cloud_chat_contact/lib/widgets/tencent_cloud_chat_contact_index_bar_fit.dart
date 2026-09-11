import 'dart:math';

import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';

/// Fits the A-Z index bar of an [AzListView] to the height the list gets.
///
/// The bar is a non-scrolling Column of fixed [AzListView.indexBarItemHeight]
/// rows inside the list's bounded Stack. At the default 16 px per letter, 20+
/// tags need 320+ px — more than a landscape phone has left under the
/// contacts toolbar — and the Column overflows. Compute this from a
/// [LayoutBuilder] wrapped around the list (never from the screen size: the
/// list may live in a pane) and pass the three fields straight through.
class TencentCloudChatIndexBarFit {
  const TencentCloudChatIndexBarFit._({
    required this.tags,
    required this.itemHeight,
    required this.options,
  });

  /// Value for [AzListView.indexBarData]; empty when the bar is hidden.
  final List<String> tags;

  /// Value for [AzListView.indexBarItemHeight].
  final double itemHeight;

  /// Value for [AzListView.indexBarOptions]; the glyph size follows
  /// [itemHeight] so shrunken rows don't draw overlapping letters.
  final IndexBarOptions options;

  static const IndexBarOptions _defaultOptions = IndexBarOptions();

  /// Smallest row that still reads as a letter; below this the bar is hidden.
  static const double _minItemHeight = 8.0;

  /// [textScale] is the ambient text scale (`MediaQuery.textScalerOf(context)
  /// .scale(1.0)`): the IndexBar's Text is scaled by it, so the logical font
  /// size is divided by it to keep the rendered glyph inside the row.
  static TencentCloudChatIndexBarFit fit(List<String> tags, double maxHeight,
      {double textScale = 1.0}) {
    final double itemHeight = fitIndexBarItemHeight(maxHeight, tags.length);
    if (itemHeight <= 0) {
      return const TencentCloudChatIndexBarFit._(
        tags: <String>[],
        itemHeight: kIndexBarItemHeight,
        options: _defaultOptions,
      );
    }
    final double defaultFontSize = _defaultOptions.textStyle.fontSize ?? 12.0;
    final double scale = textScale > 0 && textScale.isFinite ? textScale : 1.0;
    return TencentCloudChatIndexBarFit._(
      tags: tags,
      itemHeight: itemHeight,
      options: IndexBarOptions(
        textStyle: _defaultOptions.textStyle.copyWith(
          fontSize: min(defaultFontSize,
                  defaultFontSize * itemHeight / kIndexBarItemHeight) /
              scale,
        ),
      ),
    );
  }
}

/// Per-letter row height that lets [tagCount] letters fit in [maxHeight]:
/// the default 16 when there is room, shrunk down to 8, or 0 when even that
/// does not fit (callers then hide the bar). An unbounded [maxHeight] keeps
/// the default; the AzListView itself would fail to lay out there anyway.
double fitIndexBarItemHeight(double maxHeight, int tagCount) {
  if (tagCount <= 0 || !maxHeight.isFinite) {
    return kIndexBarItemHeight;
  }
  // +1 leaves a row of slack so the bar never touches both edges exactly.
  final double perTag = maxHeight / (tagCount + 1);
  if (perTag < TencentCloudChatIndexBarFit._minItemHeight) {
    return 0;
  }
  return min(kIndexBarItemHeight, perTag);
}
