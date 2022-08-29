import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_file_utils/flutter_file_utils.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FutureBuilder(
            future: buildImages(),
            builder: (BuildContext context, AsyncSnapshot snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 0.0,
                    mainAxisSpacing: 0.0,
                  ),
                  primary: false,
                  itemCount: snapshot.data.length,

                  itemBuilder: (context, index) {
                    return Image.file(snapshot.data[index]);
                  },
                );
              } else if (snapshot.connectionState == ConnectionState.waiting) {
                return Text("Loading");
              }
              return Container();
            }),
      ),
    );
  }

  Future<List<File>> buildImages() async {
    var root = await getExternalStorageDirectory();
    if(root==null)return [];
    var files =
        await FileManager(root: root).filesTree(extensions: ["png", "jpg"]);
  
    return files;
  }
}