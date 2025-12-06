import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/seed_data.dart';
import '../../models/food_models.dart';

abstract class FoodDataSource {
  Future<void> initialize();
  Future<List<FoodCategory>> fetchCategories();
  Future<List<FoodItem>> fetchTopItemsByCategory(int categoryId, {int limit});
  Future<List<FoodItem>> searchItems(String query, {int categoryId});
  Future<void> incrementUsage(int itemId);
}

class FoodDatabase implements FoodDataSource {
  FoodDatabase._();
  static final FoodDatabase instance = FoodDatabase._();

  static const _dbName = 'food_density.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<void> initialize() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE FoodCategories(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE FoodItems(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        density_g_cm3 REAL NOT NULL,
        calories_per_g REAL NOT NULL,
        usage_count INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(category_id) REFERENCES FoodCategories(id)
      );
    ''');
  }

  Future<void> _seed(Database db) async {
    final batch = db.batch();
    for (final category in SeedData.categories) {
      batch.insert('FoodCategories', {
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
      });
    }
    for (final item in SeedData.items) {
      batch.insert('FoodItems', {
        'id': item.id,
        'name': item.name,
        'category_id': item.categoryId,
        'density_g_cm3': item.density,
        'calories_per_g': item.caloriesPerGram,
        'usage_count': item.usageCount,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<FoodCategory>> fetchCategories() async {
    final db = _ensureDb();
    final rows = await db.query('FoodCategories');
    return rows
        .map((row) => FoodCategory(
              id: row['id'] as int,
              name: row['name'] as String,
              icon: row['icon'] as String,
            ))
        .toList();
  }

  Future<List<FoodItem>> fetchTopItemsByCategory(int categoryId, {int limit = 5}) async {
    final db = _ensureDb();
    final rows = await db.query(
      'FoodItems',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'usage_count DESC, name ASC',
      limit: limit,
    );
    return rows
        .map((row) => FoodItem(
              id: row['id'] as int,
              name: row['name'] as String,
              categoryId: row['category_id'] as int,
              density: (row['density_g_cm3'] as num).toDouble(),
              caloriesPerGram: (row['calories_per_g'] as num).toDouble(),
              usageCount: row['usage_count'] as int,
            ))
        .toList();
  }

  Future<List<FoodItem>> searchItems(String query, {int categoryId = 0}) async {
    final db = _ensureDb();
    final where = StringBuffer('LOWER(name) LIKE ?');
    final args = ['%${query.toLowerCase()}%'];
    if (categoryId > 0) {
      where.write(' AND category_id = ?');
      args.add(categoryId.toString());
    }
    final rows = await db.query(
      'FoodItems',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'usage_count DESC, name ASC',
    );
    return rows
        .map((row) => FoodItem(
              id: row['id'] as int,
              name: row['name'] as String,
              categoryId: row['category_id'] as int,
              density: (row['density_g_cm3'] as num).toDouble(),
              caloriesPerGram: (row['calories_per_g'] as num).toDouble(),
              usageCount: row['usage_count'] as int,
            ))
        .toList();
  }

  Future<void> incrementUsage(int itemId) async {
    final db = _ensureDb();
    await db.rawUpdate(
      'UPDATE FoodItems SET usage_count = usage_count + 1 WHERE id = ?',
      [itemId],
    );
  }

  Database _ensureDb() {
    final db = _db;
    if (db == null) {
      throw StateError('Database not initialized');
    }
    return db;
  }
}
