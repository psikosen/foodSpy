import '../models/food_models.dart';

class SeedData {
  static const categories = <FoodCategory>[
    FoodCategory(id: 1, name: 'Meat', icon: '🥩'),
    FoodCategory(id: 2, name: 'Carbs', icon: '🍚'),
    FoodCategory(id: 3, name: 'Vegetables', icon: '🥦'),
    FoodCategory(id: 4, name: 'Fruit', icon: '🍎'),
  ];

  static const items = <FoodItem>[
    // Meat
    FoodItem(id: 1, name: 'Chicken Breast', categoryId: 1, density: 1.05, caloriesPerGram: 1.65),
    FoodItem(id: 2, name: 'Salmon', categoryId: 1, density: 1.08, caloriesPerGram: 2.08),
    FoodItem(id: 3, name: 'Ribeye Steak', categoryId: 1, density: 1.00, caloriesPerGram: 2.91),
    FoodItem(id: 4, name: 'Pork Loin', categoryId: 1, density: 1.06, caloriesPerGram: 2.42),
    FoodItem(id: 5, name: 'Ground Beef 90%', categoryId: 1, density: 1.02, caloriesPerGram: 2.50),
    FoodItem(id: 6, name: 'Turkey Breast', categoryId: 1, density: 1.04, caloriesPerGram: 1.60),
    FoodItem(id: 7, name: 'Lamb Chop', categoryId: 1, density: 0.98, caloriesPerGram: 2.82),
    FoodItem(id: 8, name: 'Shrimp', categoryId: 1, density: 1.08, caloriesPerGram: 0.99),
    FoodItem(id: 9, name: 'Tuna', categoryId: 1, density: 1.10, caloriesPerGram: 1.32),
    FoodItem(id: 10, name: 'Duck Breast', categoryId: 1, density: 1.03, caloriesPerGram: 3.00),

    // Carbs
    FoodItem(id: 11, name: 'White Rice', categoryId: 2, density: 0.96, caloriesPerGram: 1.30),
    FoodItem(id: 12, name: 'Brown Rice', categoryId: 2, density: 0.97, caloriesPerGram: 1.23),
    FoodItem(id: 13, name: 'Pasta', categoryId: 2, density: 0.82, caloriesPerGram: 1.31),
    FoodItem(id: 14, name: 'Quinoa', categoryId: 2, density: 0.92, caloriesPerGram: 1.20),
    FoodItem(id: 15, name: 'Bread', categoryId: 2, density: 0.27, caloriesPerGram: 2.65),
    FoodItem(id: 16, name: 'Sweet Potato', categoryId: 2, density: 0.72, caloriesPerGram: 0.86),
    FoodItem(id: 17, name: 'Potato', categoryId: 2, density: 0.71, caloriesPerGram: 0.77),
    FoodItem(id: 18, name: 'Bagel', categoryId: 2, density: 0.40, caloriesPerGram: 2.50),
    FoodItem(id: 19, name: 'Tortilla', categoryId: 2, density: 0.45, caloriesPerGram: 3.10),
    FoodItem(id: 20, name: 'Oats', categoryId: 2, density: 0.40, caloriesPerGram: 3.89),

    // Vegetables
    FoodItem(id: 21, name: 'Broccoli', categoryId: 3, density: 0.35, caloriesPerGram: 0.34),
    FoodItem(id: 22, name: 'Spinach', categoryId: 3, density: 0.30, caloriesPerGram: 0.23),
    FoodItem(id: 23, name: 'Kale', categoryId: 3, density: 0.32, caloriesPerGram: 0.35),
    FoodItem(id: 24, name: 'Carrots', categoryId: 3, density: 0.64, caloriesPerGram: 0.41),
    FoodItem(id: 25, name: 'Peppers', categoryId: 3, density: 0.52, caloriesPerGram: 0.26),
    FoodItem(id: 26, name: 'Zucchini', categoryId: 3, density: 0.60, caloriesPerGram: 0.17),
    FoodItem(id: 27, name: 'Mushrooms', categoryId: 3, density: 0.25, caloriesPerGram: 0.22),
    FoodItem(id: 28, name: 'Tomatoes', categoryId: 3, density: 0.95, caloriesPerGram: 0.18),
    FoodItem(id: 29, name: 'Onions', categoryId: 3, density: 0.94, caloriesPerGram: 0.40),
    FoodItem(id: 30, name: 'Green Beans', categoryId: 3, density: 0.62, caloriesPerGram: 0.35),
    FoodItem(id: 31, name: 'Cauliflower', categoryId: 3, density: 0.45, caloriesPerGram: 0.25),
    FoodItem(id: 32, name: 'Asparagus', categoryId: 3, density: 0.40, caloriesPerGram: 0.20),
    FoodItem(id: 33, name: 'Cabbage', categoryId: 3, density: 0.56, caloriesPerGram: 0.25),

    // Fruit
    FoodItem(id: 34, name: 'Apple', categoryId: 4, density: 0.80, caloriesPerGram: 0.52),
    FoodItem(id: 35, name: 'Banana', categoryId: 4, density: 0.94, caloriesPerGram: 0.89),
    FoodItem(id: 36, name: 'Grapes', categoryId: 4, density: 1.09, caloriesPerGram: 0.69),
    FoodItem(id: 37, name: 'Strawberries', categoryId: 4, density: 0.96, caloriesPerGram: 0.32),
    FoodItem(id: 38, name: 'Blueberries', categoryId: 4, density: 0.92, caloriesPerGram: 0.57),
    FoodItem(id: 39, name: 'Orange', categoryId: 4, density: 0.84, caloriesPerGram: 0.47),
    FoodItem(id: 40, name: 'Pineapple', categoryId: 4, density: 0.95, caloriesPerGram: 0.50),
    FoodItem(id: 41, name: 'Mango', categoryId: 4, density: 1.09, caloriesPerGram: 0.60),
    FoodItem(id: 42, name: 'Kiwi', categoryId: 4, density: 1.00, caloriesPerGram: 0.61),
    FoodItem(id: 43, name: 'Watermelon', categoryId: 4, density: 0.96, caloriesPerGram: 0.30),
    FoodItem(id: 44, name: 'Peach', categoryId: 4, density: 0.93, caloriesPerGram: 0.42),
    FoodItem(id: 45, name: 'Pear', categoryId: 4, density: 0.98, caloriesPerGram: 0.57),
    FoodItem(id: 46, name: 'Papaya', categoryId: 4, density: 0.92, caloriesPerGram: 0.43),
    FoodItem(id: 47, name: 'Plum', categoryId: 4, density: 0.78, caloriesPerGram: 0.46),
    FoodItem(id: 48, name: 'Cherry', categoryId: 4, density: 1.10, caloriesPerGram: 0.63),
    FoodItem(id: 49, name: 'Blackberry', categoryId: 4, density: 0.94, caloriesPerGram: 0.43),
    FoodItem(id: 50, name: 'Cantaloupe', categoryId: 4, density: 0.96, caloriesPerGram: 0.34),
  ];
}
