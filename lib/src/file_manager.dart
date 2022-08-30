// dart
import 'dart:async';
import 'dart:io';

// packages
import 'package:path/path.dart' as p;

// local files
import 'sorting.dart';
import 'filter.dart';
import 'file_system_utils.dart';
import 'exceptions.dart';

final String permissionMessage = '''
    \n
    Try to add thes lines to your AndroidManifest.xml file

          `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>`
          `<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>`

    and grant storage permissions to your applicaion from app settings
    \n
''';

class FileManager {
  // The start point .
  final Directory root;

  final FileFilter? filter;

  FileManager({required this.root, this.filter}) : assert(root != null);

  /// * This function returns a [List] of [int howMany] of type [File] of recently created files.
  /// * [excludeHidded] if [true] hidden files will not be returned
  /// * sortedBy: [Sorting]
  /// * [bool] reversed: in case parameter sortedBy is used
  Future<List<dynamic>> recentFilesAndDirs(int count,
      {List<String>? extensions,
      List<String>? excludedPaths,
      excludeHidden: false,
      recursive: false,
      FlutterFileUtilsSorting? sortedBy,
      bool reversed: false}) async {
    List<File> filesPaths = await filesTree(
        recursive: recursive,
        excludedPaths: excludedPaths,
        extensions: extensions,
        excludeHidden: excludeHidden);

    // note: in case that number of recent files are not sufficient, we limit the [howMany]
    // to the number of the found ones
    if (filesPaths.length < count) count = filesPaths.length;

    var _sorted =
        sortBy(filesPaths, FlutterFileUtilsSorting.Date, reversed: true);

    // decrease length to howMany
    _sorted = _sorted.getRange(0, count).toList();

    if (sortedBy != null) {
      return sortBy(filesPaths, sortedBy, reversed: reversed);
    }

    return _sorted;
  }

  /// Return list tree of directories.
  /// You may exclude some directories from the list.
  /// * [excludedPaths] will excluded paths and their subpaths from the final [list]
  /// * sortedBy: [FlutterFileUtilsSorting]
  /// * [bool] reversed: in case parameter sortedBy is used
  Future<List<Directory>> dirsTree(
      {List<String>? excludedPaths,
      bool followLinks: false,
      bool excludeHidden: false,
      bool recursive: false,
      FlutterFileUtilsSorting? sortedBy}) async {
    List<Directory> dirs = [];

    try {
      var contents = root.listSync(recursive: recursive, followLinks: followLinks);
      if (excludedPaths != null) {
        for (var fileOrDir in contents) {
          if (fileOrDir is Directory) {
            for (var excludedPath in excludedPaths) {
              if (!p.isWithin(excludedPath, p.normalize(fileOrDir.path))) {
                if (!excludeHidden) {
                  dirs.add(Directory(p.normalize(fileOrDir.absolute.path)));
                } else {
                  if (!fileOrDir.absolute.path.contains(RegExp(r"\.[\w]+"))) {
                    dirs.add(Directory(p.normalize(fileOrDir.absolute.path)));
                  }
                }
              }
            }
          }
        }
      } else {
        for (var fileOrDir in contents) {
          if (fileOrDir is Directory) {
            if (!excludeHidden) {
              dirs.add(Directory(p.normalize(fileOrDir.absolute.path)));
            } else {
              // The Regex below is used to check if the directory contains
              // ".file" in pathe
              if (!fileOrDir.absolute.path.contains(RegExp(r"\.[\w]+"))) {
                dirs.add(Directory(p.normalize(fileOrDir.absolute.path)));
              }
            }
          }
        }
      }
    } catch (error) {
      throw FileManagerError(permissionMessage + error.toString());
    }
    if (sortedBy != null) {
      return sortBy(dirs, sortedBy) as List<Directory>;
    }

    return dirs;
  }

  /// Return tree [List] of files starting from the root of type [File]
  /// * [excludedPaths] example: '/storage/emulated/0/Android' no files will be
  ///   returned from this path, and its sub directories
  /// * sortedBy: [Sorting]
  /// * [bool] reversed: in case parameter sortedBy is used
  Future<List<File>> filesTree(
      {List<String>? extensions,
      List<String>? excludedPaths,
      excludeHidden = false,
      bool reversed: false,
      bool recursive: false,
      FlutterFileUtilsSorting? sortedBy}) async {
    List<File> files = [];

    List<Directory> dirs = await dirsTree(
        recursive:recursive,excludedPaths: excludedPaths, excludeHidden: excludeHidden);

    dirs.insert(0, Directory(root.path));

    if (extensions != null) {
      for (var dir in dirs) {
        for (var file
            in await listFiles(dir.absolute.path, extensions: extensions)) {
          if (excludeHidden) {
            if (!file.path.startsWith("."))
              files.add(file);
            else
              print("Excluded: ${file.path}");
          } else {
            files.add(file);
          }
        }
      }
    } else {
      for (var dir in dirs) {
        for (var file in await listFiles(dir.absolute.path)) {
          if (excludeHidden) {
            if (!file.path.startsWith("."))
              files.add(file);
            else
              print("Excluded: ${file.path}");
          } else {
            files.add(file);
          }
        }
      }
    }

    if (sortedBy != null) {
      return sortBy(files, sortedBy) as List<File>;
    }

    return files;
  }

  /// Return tree [List] of files starting from the root of type [File].
  ///
  /// This function uses filter
  Stream<FileSystemEntity> walk({followLinks: false,recursive:false}) async* {
    if (filter != null) {
      try {
        yield* Directory(root.path)
            .list(recursive: recursive, followLinks: followLinks)
            .transform(StreamTransformer.fromHandlers(
                handleData: (FileSystemEntity fileOrDir, EventSink eventSink) {
          if (filter!.isValid(fileOrDir.absolute.path, root.absolute.path)) {
            eventSink.add(fileOrDir);
          }
        }));
      } catch (error) {
        throw FileManagerError(permissionMessage + error.toString());
      }
    } else {
      print("Flutter File Manager: walk: No filter");
      yield* Directory(root.path)
          .list(recursive: recursive, followLinks: followLinks);
    }
  }

  /// Returns a list of found items of [Directory] or [File] type or empty list.
  /// You may supply `Regular Expression` e.g: "*\.png", instead of string.
  /// * [filesOnly] if set to [true] return only files
  /// * [dirsOnly] if set to [true] return only directories
  /// * You can set both to [true]
  /// * sortedBy: [Sorting]
  /// * [bool] reversed: in case parameter sortedBy is used
  /// * Example:
  /// * List<String> imagesPaths = await FileManager.search("myFile.png");
  Future<List<dynamic>> searchFuture(
    var keyword, {
    List<String>? excludedPaths,
    filesOnly = false,
    dirsOnly = false,
    List<String> extensions = const <String>[],
    bool reversed: false,
    bool recursive: false,
    FlutterFileUtilsSorting? sortedBy,
  }) async {
    print("Searching for: $keyword");
    // files that will be returned
    List<dynamic> founds = [];

    if (keyword.length == 0 || keyword == null) {
      throw Exception("search keyword == null");
    }

    List<Directory> dirs = await dirsTree(recursive:recursive,excludedPaths: excludedPaths);
    List<File> files =
        await filesTree(recursive:recursive,excludedPaths: excludedPaths, extensions: extensions);

    if (filesOnly == false && dirsOnly == false) {
      filesOnly = true;
      dirsOnly = true;
    }
    if (extensions.isNotEmpty) dirsOnly = false;
    // in the future fileAndDirTree will be used
    // searching in files
    if (dirsOnly == true) {
      for (var dir in dirs) {
        if (dir.absolute.path.contains(keyword)) {
          founds.add(dir);
        }
      }
    }
    // searching in files

    if (filesOnly == true) {
      for (var file in files) {
        if (file.absolute.path.contains(keyword)) {
          founds.add(file);
        }
      }
    }

    // sorting
    if (sortedBy != null) {
      return sortBy(founds, sortedBy);
    }
    return founds;
  }

  /// Returns a list of found items of [Directory] or [File] type or empty list.
  /// You may supply `Regular Expression` e.g: "*\.png", instead of string.
  /// * [filesOnly] if set to [true] return only files
  /// * [dirsOnly] if set to [true] return only directories
  /// * You can set both to [true]
  /// * sortedBy: [FlutterFileUtilsSorting]
  /// * [bool] reverse: in case parameter sortedBy is used
  /// * Example:
  /// * `List<String> imagesPaths = await FileManager.search("myFile.png").toList();`
  Stream<FileSystemEntity> search(
    var keyword, {
    bool recursive:false,
    FileFilter? searchFilter,
    FlutterFileUtilsSorting? sortedBy,
  }) async* {
    try {
      if (keyword.length == 0 || keyword == null) {
        throw FileManagerError("search keyword == null");
      }
      if (searchFilter != null) {
        print("Using default filter");
        yield* root.list(recursive: recursive, followLinks: true).where((test) {
          if (searchFilter.isValid(test.absolute.path, root.absolute.path)) {
            return getBaseName(test.path, extension: true).contains(keyword);
          }
          return false;
        });
      } else if (filter != null) {
        print("Using default filter");
        yield* root.list(recursive: recursive, followLinks: true).where((test) {
          if (filter!.isValid(test.absolute.path, root.absolute.path)) {
            return getBaseName(test.path, extension: true).contains(keyword);
          }
          return false;
        });
      } else {
        yield* root.list(recursive: recursive, followLinks: true).where((test) =>
            getBaseName(test.path, extension: true).contains(keyword));
      }
    } on FileSystemException catch (e) {
      throw FileManagerError(permissionMessage + ' ' + e.toString());
    } catch (e) {
      throw FileManagerError(e.toString());
    }
  }
}
