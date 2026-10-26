import 'package:flutter/material.dart';

/// Colour keys a category can use, in the order the colour picker shows them. The theme turns a
/// key into a colour (and a colour-blind safe one when that option is on).
const kCategoryColorKeys = [
  'food',
  'bills',
  'transport',
  'fun',
  'health',
  'other',
  'red',
  'coral',
  'orange',
  'yellow',
  'lime',
  'green',
  'mint',
  'teal',
  'cyan',
  'sky',
  'indigo',
  'navy',
  'violet',
  'purple2',
  'magenta',
  'pink',
  'brown',
  'sand',
  'olive',
  'slate',
];

/// Icons a category can use, by the name stored with the category.
const kCategoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'receipt': Icons.receipt_long,
  'directions_bus': Icons.directions_bus,
  'celebration': Icons.celebration,
  'favorite': Icons.favorite,
  'shopping_cart': Icons.shopping_cart,
  'home': Icons.home,
  'school': Icons.school,
  'pets': Icons.pets,
  'category': Icons.category,
  'local_cafe': Icons.local_cafe,
  'fastfood': Icons.fastfood,
  'local_grocery_store': Icons.local_grocery_store,
  'local_gas_station': Icons.local_gas_station,
  'directions_car': Icons.directions_car,
  'flight': Icons.flight,
  'hotel': Icons.hotel,
  'shopping_bag': Icons.shopping_bag,
  'checkroom': Icons.checkroom,
  'devices': Icons.devices,
  'phone_android': Icons.phone_android,
  'wifi': Icons.wifi,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'build': Icons.build,
  'chair': Icons.chair,
  'local_pharmacy': Icons.local_pharmacy,
  'medical_services': Icons.medical_services,
  'fitness_center': Icons.fitness_center,
  'spa': Icons.spa,
  'content_cut': Icons.content_cut,
  'child_care': Icons.child_care,
  'toys': Icons.toys,
  'sports_esports': Icons.sports_esports,
  'movie': Icons.movie,
  'music_note': Icons.music_note,
  'menu_book': Icons.menu_book,
  'card_giftcard': Icons.card_giftcard,
  'volunteer_activism': Icons.volunteer_activism,
  'savings': Icons.savings,
  'account_balance': Icons.account_balance,
  'security': Icons.security,
  'subscriptions': Icons.subscriptions,
  'work': Icons.work,
  'park': Icons.park,
  'beach_access': Icons.beach_access,
  'directions_bike': Icons.directions_bike,
  'local_laundry_service': Icons.local_laundry_service,
  'cleaning_services': Icons.cleaning_services,
};

/// Material icon for a stored icon name; a plain category icon for names it does not know.
IconData categoryIconData(String? name) =>
    kCategoryIcons[name] ?? Icons.category;

/// A ready-made category the person can add with one tap.
class SuggestedCategory {
  const SuggestedCategory(this.name, this.icon, this.color);
  final String name;
  final String icon;
  final String color;
}

const kSuggestedCategories = [
  SuggestedCategory('Groceries', 'local_grocery_store', 'green'),
  SuggestedCategory('Dining out', 'restaurant', 'orange'),
  SuggestedCategory('Coffee', 'local_cafe', 'brown'),
  SuggestedCategory('Takeaway', 'fastfood', 'coral'),
  SuggestedCategory('Rent', 'home', 'navy'),
  SuggestedCategory('Utilities', 'bolt', 'yellow'),
  SuggestedCategory('Water', 'water_drop', 'cyan'),
  SuggestedCategory('Phone and internet', 'wifi', 'sky'),
  SuggestedCategory('Insurance', 'security', 'slate'),
  SuggestedCategory('Fuel', 'local_gas_station', 'red'),
  SuggestedCategory('Car', 'directions_car', 'indigo'),
  SuggestedCategory('Public transport', 'directions_bus', 'teal'),
  SuggestedCategory('Shopping', 'shopping_bag', 'magenta'),
  SuggestedCategory('Clothing', 'checkroom', 'pink'),
  SuggestedCategory('Electronics', 'devices', 'violet'),
  SuggestedCategory('Home and garden', 'chair', 'olive'),
  SuggestedCategory('Repairs', 'build', 'slate'),
  SuggestedCategory('Pharmacy', 'local_pharmacy', 'mint'),
  SuggestedCategory('Doctor', 'medical_services', 'red'),
  SuggestedCategory('Fitness', 'fitness_center', 'lime'),
  SuggestedCategory('Personal care', 'spa', 'purple2'),
  SuggestedCategory('Haircut', 'content_cut', 'coral'),
  SuggestedCategory('Kids', 'child_care', 'sand'),
  SuggestedCategory('Toys', 'toys', 'orange'),
  SuggestedCategory('Pets', 'pets', 'brown'),
  SuggestedCategory('Education', 'school', 'indigo'),
  SuggestedCategory('Books', 'menu_book', 'navy'),
  SuggestedCategory('Entertainment', 'movie', 'violet'),
  SuggestedCategory('Games', 'sports_esports', 'purple2'),
  SuggestedCategory('Music', 'music_note', 'pink'),
  SuggestedCategory('Subscriptions', 'subscriptions', 'sky'),
  SuggestedCategory('Travel', 'flight', 'cyan'),
  SuggestedCategory('Hotels', 'hotel', 'teal'),
  SuggestedCategory('Holiday', 'beach_access', 'yellow'),
  SuggestedCategory('Gifts', 'card_giftcard', 'magenta'),
  SuggestedCategory('Charity', 'volunteer_activism', 'red'),
  SuggestedCategory('Savings', 'savings', 'green'),
  SuggestedCategory('Taxes and fees', 'account_balance', 'slate'),
  SuggestedCategory('Laundry', 'local_laundry_service', 'cyan'),
  SuggestedCategory('Cleaning', 'cleaning_services', 'mint'),
];

/// An icon and colour for a category called [name], from its words ("Grocery run" gets the
/// grocery icon). Names that match nothing get the plain category icon and [fallbackColor].
({String icon, String color}) guessCategoryStyle(
  String name, {
  String fallbackColor = 'other',
}) {
  final n = name.toLowerCase();
  const words = {
    'grocer': 'Groceries',
    'supermarket': 'Groceries',
    'restaurant': 'Dining out',
    'dining': 'Dining out',
    'coffee': 'Coffee',
    'cafe': 'Coffee',
    'rent': 'Rent',
    'electric': 'Utilities',
    'utilit': 'Utilities',
    'internet': 'Phone and internet',
    'phone': 'Phone and internet',
    'insur': 'Insurance',
    'fuel': 'Fuel',
    'petrol': 'Fuel',
    'gas': 'Fuel',
    'car': 'Car',
    'bus': 'Public transport',
    'train': 'Public transport',
    'cloth': 'Clothing',
    'shop': 'Shopping',
    'electron': 'Electronics',
    'pharm': 'Pharmacy',
    'doctor': 'Doctor',
    'gym': 'Fitness',
    'fitness': 'Fitness',
    'hair': 'Haircut',
    'kid': 'Kids',
    'child': 'Kids',
    'toy': 'Toys',
    'pet': 'Pets',
    'school': 'Education',
    'educat': 'Education',
    'book': 'Books',
    'movie': 'Entertainment',
    'cinema': 'Entertainment',
    'game': 'Games',
    'music': 'Music',
    'subscri': 'Subscriptions',
    'travel': 'Travel',
    'flight': 'Travel',
    'hotel': 'Hotels',
    'holiday': 'Holiday',
    'gift': 'Gifts',
    'charity': 'Charity',
    'saving': 'Savings',
    'tax': 'Taxes and fees',
    'laundry': 'Laundry',
    'clean': 'Cleaning',
  };
  for (final e in words.entries) {
    if (n.contains(e.key)) {
      final s = kSuggestedCategories.firstWhere((c) => c.name == e.value);
      return (icon: s.icon, color: s.color);
    }
  }
  return (icon: 'category', color: fallbackColor);
}
