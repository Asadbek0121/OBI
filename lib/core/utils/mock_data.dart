// Mock Data 
class MockData {
  static final List<Map<String, dynamic>> inventory = [
    {
      "name": "Ethanol 96%",
      "category": "Reagent",
      "stock": "500 ml", 
      "expiry": "2024-12-10",
      "status": "Healthy"
    },
    {
      "name": "Latex Gloves (M)",
      "category": "Consumable",
      "stock": "12 Boxes",
      "expiry": "2025-06-20",
      "status": "Low Stock"
    },
    {
      "name": "Glucose Reagent",
      "category": "Reagent",
      "stock": "5 kits",
      "expiry": "2024-02-15",
      "status": "Critical"
    },
    {
      "name": "Syringes 5ml",
      "category": "Consumable",
      "stock": "500 pcs",
      "expiry": "2026-01-01",
      "status": "Healthy"
    },
  ];

  static final List<Map<String, dynamic>> transactions = [
    {
      "type": "OUT",
      "item": "Ethanol 96%",
      "user": "Dr. Aziza",
      "qty": "50ml",
      "date": "10:30 AM"
    },
    {
      "type": "IN",
      "item": "Syringes 5ml",
      "user": "Manager",
      "qty": "10 Boxes",
      "date": "09:15 AM"
    },
    {
      "type": "OUT",
      "item": "Glucose Reagent",
      "user": "Lab Tech 1",
      "qty": "1 kit",
      "date": "Yesterday"
    },
  ];
}
