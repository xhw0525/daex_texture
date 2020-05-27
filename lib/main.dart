import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'BPage.dart';

void main() => runApp(MyApp());
class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}
class MyHomePage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _MyHomePageS();
}

class _MyHomePageS extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("A"),
      ),
      body: Center(),
      floatingActionButton: FloatingActionButton(onPressed: () {
        Navigator.push(
          context,
          new MaterialPageRoute(
              builder: (context) => new BPage()),
        );
      }),
    );
  }
}
