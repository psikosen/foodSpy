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
