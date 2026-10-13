import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:anti_pinhole/services/database_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop database factory should be initialized for native SQLite', () {
    initializeDatabaseFactory();
    expect(databaseFactory, equals(databaseFactoryFfi));
  });
}
