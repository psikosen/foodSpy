import 'package:flutter_test/flutter_test.dart';
import 'package:platedepth/models/food_models.dart';
import 'package:platedepth/services/database/food_repository.dart';
import 'package:platedepth/services/database/food_database.dart';

class FoodDatabaseMock implements FoodDataSource {
  final Map<int, FoodItem> _items = {
    1: const FoodItem(id: 1, name: 'Chicken', categoryId: 1, density: 1.0, caloriesPerGram: 1.0),
    2: const FoodItem(id: 2, name: 'Beef', categoryId: 1, density: 1.0, caloriesPerGram: 1.0),
  };

  @override
  Future<void> initialize() async {}

  @override
  Future<List<FoodItem>> fetchTopItemsByCategory(int categoryId, {int limit = 5}) async {
    return _items.values.where((e) => e.categoryId == categoryId).toList()
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
  }

  @override
  Future<List<FoodItem>> searchItems(String query, {int categoryId = 0}) async {
    return fetchTopItemsByCategory(categoryId);
  }

  @override
  Future<void> incrementUsage(int itemId) async {
    final current = _items[itemId]!;
    _items[itemId] = current.incremented();
  }

  @override
  Future<List<FoodCategory>> fetchCategories() async => const [];
}

void main() {
  test('smart sorting prioritizes frequently used items', () async {
    final repo = FoodRepository(database: FoodDatabaseMock());
    final before = await repo.topItems(1);
    expect(before.first.name, 'Chicken');
    await repo.recordUsage(before.last);
    final after = await repo.topItems(1);
    expect(after.first.name, 'Beef');
  });
}
