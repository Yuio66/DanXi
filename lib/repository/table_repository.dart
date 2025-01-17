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

import 'dart:convert';

import 'package:dan_xi/model/person.dart';
import 'package:dan_xi/model/time_table.dart';
import 'package:dan_xi/repository/base_repository.dart';
import 'package:dan_xi/repository/uis_login_tool.dart';
import 'package:dan_xi/util/cache.dart';
import 'package:dan_xi/util/dio_utils.dart';
import 'package:dan_xi/util/retryer.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as DOM;

class TimeTableRepository extends BaseRepositoryWithDio {
  static const String LOGIN_URL =
      'https://uis.fudan.edu.cn/authserver/login?service=http%3A%2F%2Fjwfw.fudan.edu.cn%2Feams%2Flogin.action';
  static const String EXAM_TABLE_LOGIN_URL =
      'https://uis.fudan.edu.cn/authserver/login?service=http%3A%2F%2Fjwfw.fudan.edu.cn%2Feams%2FstdExamTable%21examTable.action';
  static const String ID_URL =
      'https://jwfw.fudan.edu.cn/eams/courseTableForStd.action';
  static const String TIME_TABLE_URL =
      'https://jwfw.fudan.edu.cn/eams/courseTableForStd!courseTable.action';
  static const String EXAM_TABLE_URL =
      'https://jwfw.fudan.edu.cn/eams/stdExamTable!examTable.action';
  static const String HOST = "https://jwfw.fudan.edu.cn/eams/";
  static const String KEY_TIMETABLE_CACHE = "timetable";

  TimeTableRepository._();

  static final _instance = TimeTableRepository._();

  factory TimeTableRepository.getInstance() => _instance;

  String _getIds(String html) {
    RegExp idMatcher = RegExp(r'(?<=ids",").+(?="\);)');
    return idMatcher.firstMatch(html).group(0);
  }

  Future<TimeTable> loadTimeTableRemotely(PersonInfo info,
      {DateTime startTime}) {
    return Retrier.tryAsyncWithFix(
        () => _loadTimeTableRemotely(startTime: startTime),
        (exception) async =>
            await UISLoginTool.loginUIS(dio, LOGIN_URL, cookieJar, info, true));
  }

  Future<TimeTable> _loadTimeTableRemotely({DateTime startTime}) async {
    Response idPage = await dio.get(ID_URL);
    String termId = _getIds(idPage.data.toString());
    Response tablePage = await dio.post(TIME_TABLE_URL,
        data: {
          "ignoreHead": "1",
          "setting.kind": "std",
          "startWeek": "1",
          "ids": termId,
          "semester.id": (await cookieJar.loadForRequest(Uri.parse(HOST)))
              .firstWhere((element) => element.name == "semester.id")
              .value
        },
        options: DioUtils.NON_REDIRECT_OPTION_WITH_FORM_TYPE);
    return TimeTable.fromHtml(startTime, tablePage.data.toString());
  }

  Future<TimeTable> loadTimeTableLocally(PersonInfo info,
      {DateTime startTime, bool forceLoadFromRemote = false}) async {
    if (startTime == null) startTime = TimeTable.defaultStartTime;
    return await Cache.get(
        KEY_TIMETABLE_CACHE,
        () => loadTimeTableRemotely(info, startTime: startTime),
        (cachedValue) => TimeTable.fromJson(jsonDecode(cachedValue)),
        (object) => jsonEncode(object.toJson()),
        validate: (value) => value != null && !forceLoadFromRemote);
  }

  @override
  String get linkHost => "jwfw.fudan.edu.cn";
}

class Test {
  final String id;
  final String name;
  final String type;
  final String date;
  final String time;
  final String location;
  final String testCategory;
  final String note;

  Test(this.id, this.name, this.type, this.date, this.time, this.location,
      this.testCategory, this.note);

  factory Test.fromHtml(DOM.Element html) {
    List<DOM.Element> elements = html.getElementsByTagName("td");
    return Test(
        elements[0].text.trim(),
        elements[2].text.trim(),
        elements[3].text.trim(),
        elements[4].text.trim(),
        elements[5].text.trim(),
        elements[6].text.trim(),
        elements[7].text.trim(),
        elements[8].text.trim());
  }
}
