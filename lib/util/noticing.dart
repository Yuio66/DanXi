/*
 *     Copyright (C) 2021  DanXi-Dev
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:dan_xi/generated/l10n.dart';
import 'package:dan_xi/util/browser_util.dart';
import 'package:dan_xi/util/platform_universal.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

/// Simple helper class to show a [SnackBar] on Material or a [CupertinoAlertDialog] on Cupertino.
class Noticing {
  static showNotice(BuildContext context, String message,
      {String confirmText, String title, bool useSnackBar = true}) async {
    if (PlatformX.isMaterial(context) && useSnackBar) {
      // Override Linkify's default text style.
      final bool isThemeDark = Theme.of(context).brightness == Brightness.dark;
      final Brightness invertBrightness =
          isThemeDark ? Brightness.light : Brightness.dark;
      final TextStyle contentTextStyle =
          Theme.of(context).snackBarTheme.contentTextStyle ??
              ThemeData(brightness: invertBrightness).textTheme.subtitle1;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Linkify(
        style: contentTextStyle,
        text: message,
        onOpen: (element) => BrowserUtil.openUrl(element.url, context),
      )));
    } else {
      await showPlatformDialog(
          context: context,
          builder: (BuildContext context) => PlatformAlertDialog(
                title: title == null ? null : Text(title),
                content: Linkify(
                  text: message,
                  onOpen: (element) =>
                      BrowserUtil.openUrl(element.url, context),
                ),
                actions: <Widget>[
                  PlatformDialogAction(
                      child: PlatformText(confirmText ?? S.of(context).i_see),
                      onPressed: () => Navigator.pop(context)),
                ],
              ));
    }
  }
}
