import '../../models/food_models.dart';
import 'food_database.dart';

class FoodRepository {
  FoodRepository({FoodDataSource? database}) : _db = database ?? FoodDatabase.instance;

  final FoodDataSource _db;

  Future<List<FoodCategory>> categories() => _db.fetchCategories();

  Future<List<FoodItem>> topItems(int categoryId, {int limit = 5}) =>
      _db.fetchTopItemsByCategory(categoryId, limit: limit);

  Future<List<FoodItem>> search(String query, {int categoryId = 0}) =>
      _db.searchItems(query, categoryId: categoryId);

  Future<void> recordUsage(FoodItem item) => _db.incrementUsage(item.id);

  Map<String, double> computeNutrition({
    required FoodItem item,
    required double volumeCm3,
    required double maskAreaCm2,
  }) {
    final massGrams = item.density * volumeCm3;
    final calories = massGrams * item.caloriesPerGram;
    return {
      'volume_cm3': volumeCm3,
      'area_cm2': maskAreaCm2,
      'mass_g': massGrams,
      'calories': calories,
    };
  }
}
