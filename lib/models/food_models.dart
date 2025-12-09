class FoodCategory {
  const FoodCategory({required this.id, required this.name, required this.icon});
  final int id;
  final String name;
  final String icon;
}

class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.density,
    required this.caloriesPerGram,
    this.usageCount = 0,
  });

  final int id;
  final String name;
  final int categoryId;
  final double density;
  final double caloriesPerGram;
  final int usageCount;

  FoodItem incremented() => FoodItem(
        id: id,
        name: name,
        categoryId: categoryId,
        density: density,
        caloriesPerGram: caloriesPerGram,
        usageCount: usageCount + 1,
      );
}

class DensityRecord {
  const DensityRecord({
    required this.itemId,
    required this.density,
    required this.caloriesPerGram,
  });

  final int itemId;
  final double density;
  final double caloriesPerGram;
}

/// A single classified food item within a meal
class MealSegment {
  const MealSegment({
    required this.id,
    required this.mealId,
    required this.foodItemId,
    required this.foodName,
    required this.categoryName,
    required this.volumeCm3,
    required this.massG,
    required this.calories,
    required this.segmentIndex,
  });

  final int id;
  final int mealId;
  final int foodItemId;
  final String foodName;
  final String categoryName;
  final double volumeCm3;
  final double massG;
  final double calories;
  final int segmentIndex; // Which segment in the original image

  Map<String, dynamic> toMap() => {
    'meal_id': mealId,
    'food_item_id': foodItemId,
    'food_name': foodName,
    'category_name': categoryName,
    'volume_cm3': volumeCm3,
    'mass_g': massG,
    'calories': calories,
    'segment_index': segmentIndex,
  };

  factory MealSegment.fromMap(Map<String, dynamic> map) => MealSegment(
    id: map['id'] as int,
    mealId: map['meal_id'] as int,
    foodItemId: map['food_item_id'] as int,
    foodName: map['food_name'] as String,
    categoryName: map['category_name'] as String,
    volumeCm3: (map['volume_cm3'] as num).toDouble(),
    massG: (map['mass_g'] as num).toDouble(),
    calories: (map['calories'] as num).toDouble(),
    segmentIndex: map['segment_index'] as int,
  );
}

/// A complete meal entry with photo and all food segments
class MealEntry {
  const MealEntry({
    required this.id,
    required this.imagePath,
    required this.timestamp,
    required this.totalCalories,
    this.segments = const [],
  });

  final int id;
  final String imagePath;
  final DateTime timestamp;
  final double totalCalories;
  final List<MealSegment> segments;

  Map<String, dynamic> toMap() => {
    'image_path': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'total_calories': totalCalories,
  };

  factory MealEntry.fromMap(Map<String, dynamic> map, {List<MealSegment> segments = const []}) => MealEntry(
    id: map['id'] as int,
    imagePath: map['image_path'] as String,
    timestamp: DateTime.parse(map['timestamp'] as String),
    totalCalories: (map['total_calories'] as num).toDouble(),
    segments: segments,
  );
}
