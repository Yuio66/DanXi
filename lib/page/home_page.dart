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
import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:dan_xi/common/constant.dart';
import 'package:dan_xi/generated/l10n.dart';
import 'package:dan_xi/model/announcement.dart';
import 'package:dan_xi/model/person.dart';
import 'package:dan_xi/model/time_table.dart';
import 'package:dan_xi/page/platform_subpage.dart';
import 'package:dan_xi/page/subpage_bbs.dart';
import 'package:dan_xi/page/subpage_main.dart';
import 'package:dan_xi/page/subpage_settings.dart';
import 'package:dan_xi/page/subpage_timetable.dart';
import 'package:dan_xi/provider/settings_provider.dart';
import 'package:dan_xi/provider/state_provider.dart';
import 'package:dan_xi/public_extension_methods.dart';
import 'package:dan_xi/repository/announcement_repository.dart';
import 'package:dan_xi/repository/table_repository.dart';
import 'package:dan_xi/repository/uis_login_tool.dart';
import 'package:dan_xi/test/test.dart';
import 'package:dan_xi/util/browser_util.dart';
import 'package:dan_xi/util/flutter_app.dart';
import 'package:dan_xi/util/noticing.dart';
import 'package:dan_xi/util/platform_universal.dart';
import 'package:dan_xi/util/stream_listener.dart';
import 'package:dan_xi/widget/login_dialog/login_dialog.dart';
import 'package:dan_xi/widget/qr_code_dialog/qr_code_dialog.dart';
import 'package:dan_xi/widget/top_controller.dart';
import 'package:dio_log/overlay_draggable_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';

void sendFduholeTokenToWatch(String token) {
  const channel = const MethodChannel('fduhole');
  channel.invokeMethod("send_token", token);
}

GlobalKey<NavigatorState> detailNavigatorKey = GlobalKey();
final QuickActions quickActions = QuickActions();

class HomePage extends StatefulWidget {
  HomePage({Key key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SharedPreferences _preferences;

  /// Listener to the failure of logging in caused by different reasons.
  ///
  /// Open up a dialog to request user to log in manually in the browser.
  static StateStreamListener<CaptchaNeededException> _captchaSubscription =
      StateStreamListener();
  static StateStreamListener<CredentialsInvalidException>
      _credentialsInvalidSubscription = StateStreamListener();

  //Dark/Light Theme Control
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
  }

  /// If we need to send the QR code to iWatch now.
  ///
  /// When notified [watchActivated], we should send it after [StateProvider.personInfo] is loaded.
  bool _needSendToWatch = false;

  /// Whether the error dialog is shown.
  /// If a dialog has been shown, we will not show a duplicated one.
  /// See [_dealWithCaptchaNeededException]
  bool _isErrorDialogShown = false;

  /// The tab page index.
  ValueNotifier<int> _pageIndex = ValueNotifier(0);

  /// List of all of the subpages. They will be displayed as tab pages.
  List<PlatformSubpage> _subpage = [];

  /// Force app to rebuild all of subpages.
  ///
  /// It's usually called when user changes his account.
  void _rebuildPage() {
    _subpage = [
      HomeSubpage(),
      BBSSubpage(),
      TimetableSubPage(),
      SettingsSubpage(),
    ];
  }

  final SystemTray _systemTray = SystemTray();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captchaSubscription.cancel();
    super.dispose();
  }

  /// Deal with login issue described at [CaptchaNeededException].
  _dealWithCaptchaNeededException() {
    if (_isErrorDialogShown) {
      return;
    }
    _isErrorDialogShown = true;
    showPlatformDialog(
        barrierDismissible: false,
        context: context,
        builder: (_) => PlatformAlertDialog(
              title: Text(S.of(context).fatal_error),
              content: Text(S.of(context).login_issue_1),
              actions: [
                if (!LoginDialog.dialogShown)
                  PlatformDialogAction(
                    child: Text(S.of(context).retry),
                    onPressed: () {
                      _isErrorDialogShown = false;
                      Navigator.of(context).pop();
                      FlutterApp.restartApp(context);
                    },
                  ),
                if (!LoginDialog.dialogShown)
                  PlatformDialogAction(
                    child: Text(S.of(context).re_login),
                    onPressed: () {
                      _isErrorDialogShown = false;
                      Navigator.of(context).pop();
                      _dealWithCredentialsInvalidException();
                    },
                  )
                else
                  PlatformDialogAction(
                    child: Text(S.of(context).cancel),
                    onPressed: () {
                      _isErrorDialogShown = false;
                      Navigator.of(context).pop();
                    },
                  ),
                PlatformDialogAction(
                  child: Text(S.of(context).login_issue_1_action),
                  onPressed: () =>
                      BrowserUtil.openUrl(Constant.UIS_URL, context),
                ),
              ],
            ));
  }

  /// Deal with login issue described at [CredentialsInvalidException].
  _dealWithCredentialsInvalidException() async {
    if (!LoginDialog.dialogShown) {
      PersonInfo.removeFromSharedPreferences(_preferences);
      FlutterApp.restartApp(context);
    }
  }

  DateTime _lastRefreshTime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // After the app returns from the background
        // Refresh the homepage if it hasn't been refreshed for 30 minutes
        // To keep the data up-to-date.
        if (_lastRefreshTime != null &&
            DateTime.now()
                    .difference(_lastRefreshTime)
                    .compareTo(Duration(minutes: 30)) >
                0) {
          _lastRefreshTime = DateTime.now();
          RefreshHomepageEvent().fire();
        }
        break;
      case AppLifecycleState.inactive:
        // Ignored
        break;
      case AppLifecycleState.paused:
        // Ignored
        break;
      case AppLifecycleState.detached:
        // Ignored
        break;
    }
  }

  Future<void> initSystemTray() async {
    if (!PlatformX.isWindows) return;
    // We first init the systray menu and then add the menu entries
    await _systemTray.initSystemTray("system tray",
        iconPath: PlatformX.createPlatformFile(
                PlatformX.getPathFromFile(Platform.resolvedExecutable) +
                    "/data/flutter_assets/assets/graphics/app_icon.ico")
            .path,
        toolTip: "DanXi is here~");
    List<MenuItemBase> showingMenu;
    List<MenuItemBase> hidingMenu;
    showingMenu = [
      MenuItem(
        label: 'Hide',
        onClicked: () {
          appWindow.hide();
          _systemTray.setContextMenu(hidingMenu);
        },
      ),
      MenuSeparator(),
      MenuItem(
        label: 'Exit',
        onClicked: () {
          appWindow.close();
          FlutterApp.exitApp();
        },
      ),
    ];
    hidingMenu = [
      MenuItem(
        label: 'Show',
        onClicked: () {
          appWindow.show();
          _systemTray.setContextMenu(showingMenu);
        },
      ),
      MenuSeparator(),
      MenuItem(
        label: 'Exit',
        onClicked: () {
          appWindow.close();
          FlutterApp.exitApp();
        },
      ),
    ];
    await _systemTray.setContextMenu(showingMenu);
  }

  @override
  void initState() {
    super.initState();
    // Init for firebase services.
    // FirebaseHandler.initFirebase();
    // Refresh the page when account changes.
    StateProvider.personInfo.addListener(() {
      if (StateProvider.personInfo.value != null) {
        _rebuildPage();
        refreshSelf();
      }
    });
    initSystemTray().catchError((ignored) {});
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
      // This callback gets invoked every time brightness changes
      // What's wrong with this code? why does the app refresh on every launch?
      // The timer below is a workaround to the issue.
      Timer(Duration(milliseconds: 500), () {
        if (WidgetsBinding.instance.platformDispatcher.platformBrightness !=
            Theme.of(context).brightness) FlutterApp.restartApp(context);
      });
    };

    _captchaSubscription.bindOnlyInvalid(
        Constant.eventBus
            .on<CaptchaNeededException>()
            .listen((_) => _dealWithCaptchaNeededException()),
        hashCode);
    _credentialsInvalidSubscription.bindOnlyInvalid(
        Constant.eventBus
            .on<CredentialsInvalidException>()
            .listen((_) => _dealWithCredentialsInvalidException()),
        hashCode);

    // Load the latest announcement & the start date of the following term.
    // Just ignore the network error.
    _loadAnnouncement().catchError((ignored) {});
    _loadStartDate().catchError((ignored) {});

    // Configure shortcut listeners on Android & iOS.
    if (PlatformX.isMobile)
      quickActions.initialize((shortcutType) {
        if (shortcutType == 'action_qr_code' &&
            StateProvider.personInfo.value != null) {
          QRHelper.showQRCode(context, StateProvider.personInfo.value);
        }
      });
    // Configure watch listeners on iOS.
    if (_needSendToWatch &&
        _preferences.containsKey(SettingsProvider.KEY_FDUHOLE_TOKEN)) {
      sendFduholeTokenToWatch(
          _preferences.getString(SettingsProvider.KEY_FDUHOLE_TOKEN));
      // Only send once.
      _needSendToWatch = false;
    }
    // Add shortcuts on Android & iOS.
    if (PlatformX.isMobile) {
      quickActions.setShortcutItems(<ShortcutItem>[
        ShortcutItem(
            type: 'action_qr_code',
            localizedTitle: S.current.fudan_qr_code,
            icon: 'ic_launcher'),
      ]);
    }
    // Init watchOS support
    const channel_a = const MethodChannel('fduhole');
    channel_a.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'get_token') {
        // If we haven't loaded [StateProvider.personInfo]
        if (_preferences.containsKey(SettingsProvider.KEY_FDUHOLE_TOKEN)) {
          sendFduholeTokenToWatch(
              _preferences.getString(SettingsProvider.KEY_FDUHOLE_TOKEN));
        } else {
          // Notify that we should send the token to watch later
          _needSendToWatch = true;
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // We have to load personInfo after [initState] and [build], since it may pop up a dialog,
    // which is not allowed in both methods. It is because that the widget's reference to its inherited widget hasn't been changed.
    // Also, otherwise it will call [setState] before the frame is completed.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadOrInitPersonInfo());
  }

  /// Load persistent data (e.g. user name, password, etc.) from the local storage.
  ///
  /// If user hasn't logged in before, request him to do so.
  void _loadOrInitPersonInfo() {
    _preferences = SettingsProvider.getInstance().preferences;

    if (PersonInfo.verifySharedPreferences(_preferences)) {
      StateProvider.personInfo.value =
          PersonInfo.fromSharedPreferences(_preferences);
      TestLifeCycle.onStart(context);
    } else {
      LoginDialog.showLoginDialog(
          context, _preferences, StateProvider.personInfo, false);
    }
  }

  /// Show an empty container, if no person info is set.
  Widget _buildDummyBody(String title) => PlatformScaffold(
        iosContentBottomPadding: false,
        iosContentPadding: true,
        // backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: PlatformAppBar(
          title: Text(title),
        ),
        body: Container(),
      );

  Widget _buildBody(String title) {
    // Build action buttons.
    PlatformIconButton leadingButton;
    List<PlatformIconButton> trailingButtons = [];
    List<AppBarButtonItem> leadingItems =
        _subpage[_pageIndex.value].leading.call(context);
    List<AppBarButtonItem> trailingItems =
        _subpage[_pageIndex.value].trailing.call(context);

    if (leadingItems.isNotEmpty) {
      leadingButton = PlatformIconButton(
        material: (_, __) =>
            MaterialIconButtonData(tooltip: leadingItems.first.caption),
        padding: EdgeInsets.zero,
        icon: leadingItems.first.widget,
        onPressed: leadingItems.first.onPressed,
      );
    }

    if (trailingItems.isNotEmpty) {
      trailingButtons = trailingItems
          .map((e) => PlatformIconButton(
                material: (_, __) => MaterialIconButtonData(tooltip: e.caption),
                padding: EdgeInsets.zero,
                icon: e.widget,
                onPressed: e.onPressed,
              ))
          .toList();
    }
    // Show debug button for [Dio].
    if (PlatformX.isDebugMode(_preferences)) showDebugBtn(context);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _pageIndex),
      ],
      child: PlatformScaffold(
        iosContentBottomPadding: false,
        iosContentPadding: false,
        appBar: PlatformAppBar(
          cupertino: (_, __) => CupertinoNavigationBarData(
            title: MediaQuery(
              data: MediaQueryData(
                  textScaleFactor: MediaQuery.textScaleFactorOf(context)),
              child: TopController(
                child: Text(title),
                controller: PrimaryScrollController.of(context),
              ),
            ),
          ),
          material: (_, __) => MaterialAppBarData(
            title: TopController(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              controller: PrimaryScrollController.of(context),
            ),
          ),
          leading: leadingButton,
          trailingActions: trailingButtons,
        ),
        body: IndexedStack(
          index: _pageIndex.value,
          children: _subpage,
        ),

        // 2021-5-19 @w568w:
        // Override the builder to prevent the repeatedly built states on iOS.
        // I don't know why it works...
        cupertinoTabChildBuilder: (_, index) => _subpage[index],
        bottomNavBar: PlatformNavBar(
          items: [
            BottomNavigationBarItem(
              //backgroundColor: Colors.purple,
              icon: PlatformX.isAndroid
                  ? Icon(Icons.dashboard)
                  : Icon(CupertinoIcons.square_stack_3d_up_fill),
              label: S.of(context).dashboard,
            ),
            BottomNavigationBarItem(
              //backgroundColor: Colors.indigo,
              icon: PlatformX.isAndroid
                  ? Icon(Icons.forum)
                  : Icon(CupertinoIcons.text_bubble),
              label: S.of(context).forum,
            ),
            BottomNavigationBarItem(
              //backgroundColor: Colors.blue,
              icon: PlatformX.isAndroid
                  ? Icon(Icons.calendar_today)
                  : Icon(CupertinoIcons.calendar),
              label: S.of(context).timetable,
            ),
            BottomNavigationBarItem(
              //backgroundColor: Theme.of(context).primaryColor,
              icon: PlatformX.isAndroid
                  ? Icon(Icons.settings)
                  : Icon(CupertinoIcons.gear_alt),
              label: S.of(context).settings,
            ),
          ],
          currentIndex: _pageIndex.value,
          material: (_, __) => MaterialNavBarData(
            type: BottomNavigationBarType.fixed,
          ),
          itemChanged: (index) {
            if (index != _pageIndex.value) {
              // Dispatch [SubpageViewState] events.
              for (int i = 0; i < _subpage.length; i++) {
                if (index != i) {
                  _subpage[i].onViewStateChanged(SubpageViewState.INVISIBLE);
                }
              }
              _subpage[index].onViewStateChanged(SubpageViewState.VISIBLE);
              setState(() => _pageIndex.value = index);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _lastRefreshTime = DateTime.now();
    String title = _subpage.isEmpty
        ? S.of(context).app_name
        : _subpage[_pageIndex.value].title.call(context);
    return StateProvider.personInfo.value == null || _subpage.isEmpty
        ? _buildDummyBody(title)
        : _buildBody(title);
  }

  Future<void> _loadAnnouncement() async {
    Announcement announcement =
        await AnnouncementRepository.getInstance().getLastNewAnnouncement();
    if (announcement != null) {
      showPlatformDialog(
          context: context,
          builder: (BuildContext context) => PlatformAlertDialog(
                title: Text(
                  S.of(context).developer_announcement(announcement.createdAt),
                ),
                content: Linkify(
                  text: announcement.content,
                  onOpen: (element) =>
                      BrowserUtil.openUrl(element.url, context),
                ),
                actions: <Widget>[
                  PlatformDialogAction(
                      child: PlatformText(S.of(context).i_see),
                      onPressed: () => Navigator.pop(context)),
                ],
              ));
    }
  }

  Future<void> _loadStartDate() async {
    TimeTable.defaultStartTime = await AnnouncementRepository.getInstance()
        .getStartDate()
        .catchError((e) {
      showPlatformDialog(
          context: context,
          builder: (BuildContext context) => PlatformAlertDialog(
                title: Text(
                  S.of(context).fatal_error,
                ),
                content: Text(S.of(context).login_issue_2),
                actions: <Widget>[
                  PlatformDialogAction(
                      child: PlatformText(S.of(context).retry),
                      onPressed: () {
                        Navigator.pop(context);
                        _loadStartDate();
                      }),
                  PlatformDialogAction(
                      child: PlatformText(S.of(context).skip),
                      onPressed: () => Navigator.pop(context)),
                ],
              ));
    });
    // Determine if Timetable needs to be updated
    if (SettingsProvider.getInstance().lastSemesterStartTime !=
            TimeTable.defaultStartTime.toIso8601String() &&
        StateProvider.personInfo.value != null) {
      // Update Timetable
      TimeTableRepository.getInstance()
          .loadTimeTableLocally(StateProvider.personInfo.value,
              forceLoadFromRemote: true)
          .onError((error, stackTrace) => Noticing.showNotice(
              context, S.of(context).timetable_refresh_error,
              title: S.of(context).fatal_error, useSnackBar: false));

      SettingsProvider.getInstance().lastSemesterStartTime =
          TimeTable.defaultStartTime.toIso8601String();
    }
  }
}
