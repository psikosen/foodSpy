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
  static const _dbVersion = 2; // Bumped for history tables

  Database? _db;

  @override
  Future<void> initialize() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
        await _createHistorySchema(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createHistorySchema(db);
        }
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

  Future<void> _createHistorySchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MealEntries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        total_calories REAL NOT NULL DEFAULT 0
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MealSegments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        meal_id INTEGER NOT NULL,
        food_item_id INTEGER NOT NULL,
        food_name TEXT NOT NULL,
        category_name TEXT NOT NULL,
        volume_cm3 REAL NOT NULL,
        mass_g REAL NOT NULL,
        calories REAL NOT NULL,
        segment_index INTEGER NOT NULL,
        FOREIGN KEY(meal_id) REFERENCES MealEntries(id) ON DELETE CASCADE,
        FOREIGN KEY(food_item_id) REFERENCES FoodItems(id)
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_meal_segments_meal_id ON MealSegments(meal_id);');
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

  // ========== Meal History Methods ==========

  /// Save a new meal entry with all its segments
  Future<int> saveMealEntry(MealEntry meal, List<MealSegment> segments) async {
    final db = _ensureDb();
    
    // Insert meal entry
    final mealId = await db.insert('MealEntries', meal.toMap());
    
    // Insert all segments
    final batch = db.batch();
    for (final segment in segments) {
      batch.insert('MealSegments', {
        'meal_id': mealId,
        'food_item_id': segment.foodItemId,
        'food_name': segment.foodName,
        'category_name': segment.categoryName,
        'volume_cm3': segment.volumeCm3,
        'mass_g': segment.massG,
        'calories': segment.calories,
        'segment_index': segment.segmentIndex,
      });
    }
    await batch.commit(noResult: true);
    
    // Update total calories
    final totalCalories = segments.fold<double>(0, (sum, s) => sum + s.calories);
    await db.update(
      'MealEntries',
      {'total_calories': totalCalories},
      where: 'id = ?',
      whereArgs: [mealId],
    );
    
    return mealId;
  }

  /// Fetch all meal entries (most recent first)
  Future<List<MealEntry>> fetchMealEntries({int limit = 50}) async {
    final db = _ensureDb();
    final rows = await db.query(
      'MealEntries',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    final meals = <MealEntry>[];
    for (final row in rows) {
      final mealId = row['id'] as int;
      final segmentRows = await db.query(
        'MealSegments',
        where: 'meal_id = ?',
        whereArgs: [mealId],
        orderBy: 'segment_index ASC',
      );
      final segments = segmentRows.map((s) => MealSegment.fromMap(s)).toList();
      meals.add(MealEntry.fromMap(row, segments: segments));
    }
    
    return meals;
  }

  /// Fetch a single meal entry with segments
  Future<MealEntry?> fetchMealEntry(int mealId) async {
    final db = _ensureDb();
    final rows = await db.query(
      'MealEntries',
      where: 'id = ?',
      whereArgs: [mealId],
    );
    
    if (rows.isEmpty) return null;
    
    final segmentRows = await db.query(
      'MealSegments',
      where: 'meal_id = ?',
      whereArgs: [mealId],
      orderBy: 'segment_index ASC',
    );
    final segments = segmentRows.map((s) => MealSegment.fromMap(s)).toList();
    
    return MealEntry.fromMap(rows.first, segments: segments);
  }

  /// Delete a meal entry and all its segments
  Future<void> deleteMealEntry(int mealId) async {
    final db = _ensureDb();
    await db.delete('MealSegments', where: 'meal_id = ?', whereArgs: [mealId]);
    await db.delete('MealEntries', where: 'id = ?', whereArgs: [mealId]);
  }

  /// Get today's total calories
  Future<double> fetchTodayCalories() async {
    final db = _ensureDb();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final result = await db.rawQuery(
      'SELECT SUM(total_calories) as total FROM MealEntries WHERE timestamp >= ? AND timestamp < ?',
      [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
    );
    
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
