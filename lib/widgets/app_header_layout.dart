import 'package:flutter/widgets.dart';
import 'package:harvest/core/utils/utils.dart';

const double kAppHeaderHeight = 52;
const double kDesktopWindowControlsInset = 14;
const double kDesktopWindowControlsReservedWidth = 102;

double appHeaderLeadingInset(BuildContext context) {
  if ((PlatformTool.isMacOS() || PlatformTool.isLinux()) && !context.isMobile) {
    return kDesktopWindowControlsReservedWidth;
  }
  return 0;
}

double appHeaderTrailingInset(BuildContext context) {
  if (PlatformTool.isWindows() && !context.isMobile) {
    return kDesktopWindowControlsReservedWidth;
  }
  return 0;
}

EdgeInsets appHeaderPadding(
  BuildContext context, {
  double left = 0,
  double top = 6,
  double right = 8,
  double bottom = 6,
}) {
  return EdgeInsets.fromLTRB(
    left + appHeaderLeadingInset(context),
    top,
    right + appHeaderTrailingInset(context),
    bottom,
  );
}
