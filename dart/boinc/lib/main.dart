import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/avd.dart';
import 'package:flutter_svg/flutter_svg.dart';


void main() => runApp(MyApp());



class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();
}

class _MyAppState extends State<MyApp> {
  /// 1) our themeMode "state" field
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode, // 2) ← ← ← use "state" field here //////////////
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }

  /// 3) Call this to change theme from any context using "of" accessor
  /// e.g.:
  /// MyApp.of(context).changeTheme(ThemeMode.dark);
  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }
}

final PictureInfoDecoder<String> avdStringDecoder =
    (String data, ColorFilter? colorFilter, String key) =>
    avd.avdPictureStringDecoder(data, false, colorFilter, key);

class MyHomePage extends StatelessWidget {
  final String title;

  MyHomePage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    AppBar appBar = AppBar(title: Text(title));
    return Scaffold(
      appBar: appBar,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Choose your theme:',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                /// //////////////////////////////////////////////////////
                /// Change theme & rebuild to show it using these buttons
                ElevatedButton(
                    onPressed: () => MyApp.of(context)?.changeTheme(ThemeMode.light),
                    child: Text('Light')
                ),
                ElevatedButton(
                  onPressed: () => MyApp.of(context)?.changeTheme(ThemeMode.dark),
                  child: Text('Dark'),
                ),
                /// //////////////////////////////////////////////////////
              ],
            ),
          ],
        ),
      ),
      drawer: Drawer(
        // Add a ListView to the drawer. This ensures the user can scroll
        // through the options in the drawer if there isn't enough vertical
        // space to fit everything.
        child: ListView(
          // Important: Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: <Widget>[
            Container(
            height: appBar.preferredSize.height,
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.rectangle,
              ),
              child: Text('Drawer Header'),
            )),
            ListTile(
              leading: AvdPicture.asset("res/drawable/ic_baseline_list.xml", color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Tasks'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_email.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Notices'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.account_tree),
              //AvdPicture.asset('res/drawable/ic_projects.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Projects'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_add_box.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Add Project'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_settings.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Preference'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_help.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Help'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_bug_report.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Report Issue'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: AvdPicture.asset('res/drawable/ic_baseline_warning.xml', color: Theme.of(context).textTheme.bodyText1?.color),
              title: Text('Event log'),
              onTap: () {
                // Update the state of the app
                // ...
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

