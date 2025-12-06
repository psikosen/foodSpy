import 'package:flutter/material.dart';
import '../../models/food_models.dart';
import '../../services/database/food_repository.dart';
import '../../theme/palette.dart';

class FoodSelectionSheet extends StatefulWidget {
  const FoodSelectionSheet({
    super.key,
    required this.repository,
    required this.onSelected,
    required this.estimatedVolume,
    required this.maskArea,
  });

  final FoodRepository repository;
  final double estimatedVolume;
  final double maskArea;
  final void Function(FoodItem item, Map<String, double> nutrition) onSelected;

  @override
  State<FoodSelectionSheet> createState() => _FoodSelectionSheetState();
}

class _FoodSelectionSheetState extends State<FoodSelectionSheet> {
  int _step = 0;
  int? _categoryId;
  List<FoodCategory> _categories = const [];
  List<FoodItem> _items = const [];
  FoodItem? _selectedItem;
  final _searchController = TextEditingController();
  late final FoodRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await _repository.categories();
    setState(() => _categories = categories);
  }

  Future<void> _loadItems() async {
    if (_categoryId == null) return;
    final items = await _repository.topItems(_categoryId!);
    setState(() => _items = items);
  }

  Future<void> _search(String query) async {
    if (_categoryId == null) return;
    final items = await _repository.search(query, categoryId: _categoryId!);
    setState(() => _items = items);
  }

  void _onItem(FoodItem item) {
    setState(() {
      _selectedItem = item;
      _step = 2;
    });
    final nutrition = _repository.computeNutrition(
      item: item,
      volumeCm3: widget.estimatedVolume,
      maskAreaCm2: widget.maskArea,
    );
    widget.onSelected(item, nutrition);
    _repository.recordUsage(item);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: Palette.deepText.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            if (_step == 0) _buildCategoryGrid(),
            if (_step == 1) _buildItemList(),
            if (_step == 2 && _selectedItem != null) _buildResult(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pick a category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          itemCount: _categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3,
          ),
          itemBuilder: (_, index) {
            final category = _categories[index];
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Palette.sky,
                foregroundColor: Palette.deepText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                setState(() {
                  _categoryId = category.id;
                  _step = 1;
                });
                _loadItems();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(category.icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(category.name),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildItemList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _step = 0),
            ),
            const Text('Top picks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search food...',
            filled: true,
            fillColor: Palette.lilac.withOpacity(0.3),
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: _search,
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          itemCount: _items.length,
          itemBuilder: (_, index) {
            final item = _items[index];
            return Card(
              color: Palette.mint.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(item.name),
                subtitle: Text('Density ${item.density.toStringAsFixed(2)} g/cm³ · ${item.caloriesPerGram.toStringAsFixed(2)} cal/g'),
                onTap: () => _onItem(item),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildResult() {
    final item = _selectedItem!;
    final nutrition = _repository.computeNutrition(
      item: item,
      volumeCm3: widget.estimatedVolume,
      maskAreaCm2: widget.maskArea,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Text(item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        _metricRow('Volume', '${nutrition['volume_cm3']!.toStringAsFixed(1)} cm³'),
        _metricRow('Area', '${nutrition['area_cm2']!.toStringAsFixed(1)} cm²'),
        _metricRow('Mass', '${nutrition['mass_g']!.toStringAsFixed(1)} g'),
        _metricRow('Calories', '${nutrition['calories']!.toStringAsFixed(0)} kcal'),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check),
          label: const Text('Done'),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Palette.deepText)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Palette.deepText)),
        ],
      ),
    );
  }
}
