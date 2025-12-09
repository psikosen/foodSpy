import 'package:flutter/material.dart';
import 'app.dart';
import 'services/database/food_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FoodDatabase.instance.initialize();
  runApp(const FoodSpyApp());
}
