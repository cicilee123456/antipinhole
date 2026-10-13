import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initializeDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    databaseFactory = databaseFactoryFfi;
  }
}
