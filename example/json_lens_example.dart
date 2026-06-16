import 'dart:convert';
import 'package:json_lens/json_lens.dart';

// ─── Sample Model ──────────────────────────────────────────────────

class HotelResponse {
  final String status;
  final HotelData data;

  HotelResponse({required this.status, required this.data});

  factory HotelResponse.fromJson(Map<String, dynamic> json) {
    return HotelResponse(
      status: json['status'],
      data: HotelData.fromJson(json['data']),
    );
  }
}

class HotelData {
  final List<Hotel> hotels;

  HotelData({required this.hotels});

  factory HotelData.fromJson(Map<String, dynamic> json) {
    return HotelData(
      hotels: (json['hotels'] as List).map((e) => Hotel.fromJson(e)).toList(),
    );
  }
}

class Hotel {
  final int id;
  final String hotelName;
  final String roomPrice; // Bug: API sends int, model expects String

  Hotel({required this.id, required this.hotelName, required this.roomPrice});

  factory Hotel.fromJson(Map<String, dynamic> json) {
    return Hotel(
      id: json['id'],
      hotelName: json['hotel_name'],
      roomPrice: json['room_price'],
    );
  }
}

// ─── Sample JSON (with intentional type mismatch) ──────────────────

const badJson = '''
{
  "status": "success",
  "data": {
    "hotels": [
      {
        "id": 1,
        "hotel_name": "Grand Palace",
        "room_price": 12500,
        "total_amount": "25000"
      }
    ]
  }
}
''';

void main() {
  final jsonMap = json.decode(badJson) as Map<String, dynamic>;

  // ─── Method 1: wrap() existing fromJson (recommended default) ────
  print('=== Method 1: wrap() existing fromJson ===\n');
  try {
    JsonDebugger.wrap<HotelResponse>(
      deserialize: () => HotelResponse.fromJson(jsonMap),
      json: jsonMap,
      tag: 'HotelResponse',
    );
  } on JsonDebugError catch (e) {
    print(e);
  }

  // ─── Method 2: decode() with schema (best precision) ─────────────
  print('\n=== Method 2: decode() with schema ===\n');
  try {
    JsonDebugger.decode<HotelResponse>(
      jsonString: badJson,
      fromJson: HotelResponse.fromJson,
      tag: 'HotelResponse',
      schema: {
        'status': String,
        'data': {
          'hotels': [
            {
              'id': int,
              'hotel_name': String,
              'room_price': String, // Schema says String, API sends int
              'total_amount': String,
            }
          ]
        }
      },
    );
  } on JsonDebugError catch (e) {
    print(e);
  }

  // ─── Method 3: validate() schema only (CI/testing) ───────────────
  print('\n=== Method 3: validate() schema only ===\n');
  final errors = JsonDebugger.validate(
    json: jsonMap,
    tag: 'HotelResponse',
    schema: {
      'status': String,
      'data': {
        'hotels': [
          {
            'id': int,
            'hotel_name': String,
            'room_price': String,
            'total_amount': String,
          }
        ]
      }
    },
  );

  if (errors.isNotEmpty) {
    print('Found ${errors.length} type mismatch(es):');
    for (final error in errors) {
      print(error);
    }
  }
}
