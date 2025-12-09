import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/food_models.dart';
import '../../services/database/food_database.dart';
import '../../theme/palette.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FoodDatabase _database = FoodDatabase.instance;
  List<MealEntry> _meals = [];
  double _todayCalories = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final meals = await _database.fetchMealEntries();
      final todayCalories = await _database.fetchTodayCalories();
      setState(() {
        _meals = meals;
        _todayCalories = todayCalories;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteMeal(MealEntry meal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Meal?'),
        content: Text(
          'This will remove the meal from ${DateFormat.yMMMd().format(meal.timestamp)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _database.deleteMealEntry(meal.id);
      // Delete image file if exists
      if (meal.imagePath.isNotEmpty) {
        try {
          await File(meal.imagePath).delete();
        } catch (_) {}
      }
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal History'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: CustomScrollView(
                slivers: [
                  // Today's summary card
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Palette.mint, Palette.sky],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today',
                            style: TextStyle(
                              color: Palette.deepText.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _todayCalories.toStringAsFixed(0),
                                style: TextStyle(
                                  color: Palette.deepText,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'kcal',
                                  style: TextStyle(
                                    color: Palette.deepText.withValues(alpha: 0.7),
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Meal list
                  if (_meals.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No meals logged yet',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Take a photo to get started!',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _MealCard(
                          meal: _meals[index],
                          onDelete: () => _deleteMeal(_meals[index]),
                          onTap: () => _showMealDetails(_meals[index]),
                        ),
                        childCount: _meals.length,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  void _showMealDetails(MealEntry meal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _MealDetailSheet(
          meal: meal,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.onDelete,
    required this.onTap,
  });

  final MealEntry meal;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = meal.imagePath.isNotEmpty && File(meal.imagePath).existsSync();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 100,
              height: 100,
              color: Palette.lilac.withValues(alpha: 0.3),
              child: hasImage
                  ? Image.file(
                      File(meal.imagePath),
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      Icons.restaurant,
                      size: 40,
                      color: Palette.deepText.withValues(alpha: 0.3),
                    ),
            ),
            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat.yMMMd().add_jm().format(meal.timestamp),
                      style: TextStyle(
                        color: Palette.deepText.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${meal.totalCalories.toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        color: Palette.deepText,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${meal.segments.length} items: ${meal.segments.map((s) => s.foodName).join(", ")}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Palette.deepText.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MealDetailSheet extends StatelessWidget {
  const _MealDetailSheet({
    required this.meal,
    required this.scrollController,
  });

  final MealEntry meal;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final hasImage = meal.imagePath.isNotEmpty && File(meal.imagePath).existsSync();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // Handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Image
        if (hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(meal.imagePath),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 16),

        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat.yMMMMd().add_jm().format(meal.timestamp),
              style: TextStyle(
                color: Palette.deepText.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Palette.mint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${meal.totalCalories.toStringAsFixed(0)} kcal',
                style: TextStyle(
                  color: Palette.deepText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Food items
        Text(
          'Food Items',
          style: TextStyle(
            color: Palette.deepText,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        ...meal.segments.map((segment) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Palette.sky.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCategoryColor(segment.categoryName),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  segment.categoryName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Food name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.foodName,
                      style: TextStyle(
                        color: Palette.deepText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${segment.massG.toStringAsFixed(0)}g · ${segment.volumeCm3.toStringAsFixed(1)} cm³',
                      style: TextStyle(
                        color: Palette.deepText.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Calories
              Text(
                '${segment.calories.toStringAsFixed(0)}',
                style: TextStyle(
                  color: Palette.deepText,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                ' kcal',
                style: TextStyle(
                  color: Palette.deepText.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'protein':
        return const Color(0xFFE57373);
      case 'grain':
        return const Color(0xFFFFD54F);
      case 'vegetable':
        return const Color(0xFF81C784);
      case 'fruit':
        return const Color(0xFFFF8A65);
      case 'dairy':
        return const Color(0xFF64B5F6);
      case 'beverage':
        return const Color(0xFF4DB6AC);
      default:
        return const Color(0xFFBA68C8);
    }
  }
}

