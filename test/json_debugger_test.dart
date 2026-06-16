import 'dart:convert';
import 'package:json_lens/json_lens.dart';
import 'package:test/test.dart';

// ─── Test Models ────────────────────────────────────────────────────

class SimpleModel {
  final String name;
  final int age;

  SimpleModel({required this.name, required this.age});

  factory SimpleModel.fromJson(Map<String, dynamic> json) {
    return SimpleModel(name: json['name'], age: json['age']);
  }
}

class NestedModel {
  final String status;
  final InnerModel data;

  NestedModel({required this.status, required this.data});

  factory NestedModel.fromJson(Map<String, dynamic> json) {
    return NestedModel(
      status: json['status'],
      data: InnerModel.fromJson(json['data']),
    );
  }
}

class InnerModel {
  final List<Item> items;

  InnerModel({required this.items});

  factory InnerModel.fromJson(Map<String, dynamic> json) {
    return InnerModel(
      items: (json['items'] as List).map((e) => Item.fromJson(e)).toList(),
    );
  }
}

class Item {
  final int id;
  final String label;
  final String price;

  Item({required this.id, required this.label, required this.price});

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'],
      label: json['label'],
      price: json['price'],
    );
  }
}

void main() {
  // ─── decode() tests ─────────────────────────────────────────────

  group('JsonDebugger.decode()', () {
    test('succeeds with valid JSON and matching schema', () {
      final jsonString = '{"name": "Alice", "age": 30}';
      final result = JsonDebugger.decode<SimpleModel>(
        jsonString: jsonString,
        fromJson: SimpleModel.fromJson,
        schema: {'name': String, 'age': int},
      );
      expect(result.name, 'Alice');
      expect(result.age, 30);
    });

    test('throws on invalid JSON syntax', () {
      expect(
        () => JsonDebugger.decode<SimpleModel>(
          jsonString: '{invalid json}',
          fromJson: SimpleModel.fromJson,
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.message,
          'message',
          'Invalid JSON syntax',
        )),
      );
    });

    test('throws when root is not a JSON object', () {
      expect(
        () => JsonDebugger.decode<SimpleModel>(
          jsonString: '"just a string"',
          fromJson: SimpleModel.fromJson,
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.message,
          'message',
          'Expected a JSON object at root',
        )),
      );
    });

    test('throws when root is a JSON array', () {
      expect(
        () => JsonDebugger.decode<SimpleModel>(
          jsonString: '[1, 2, 3]',
          fromJson: SimpleModel.fromJson,
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.message,
          'message',
          'Expected a JSON object at root',
        )),
      );
    });

    test('detects type mismatch at root level with schema', () {
      final jsonString = '{"name": 123, "age": 30}';
      expect(
        () => JsonDebugger.decode<SimpleModel>(
          jsonString: jsonString,
          fromJson: SimpleModel.fromJson,
          schema: {'name': String, 'age': int},
          tag: 'SimpleModel',
        ),
        throwsA(isA<JsonDebugError>()
            .having((e) => e.path, 'path', r'$.name')
            .having((e) => e.tag, 'tag', 'SimpleModel')),
      );
    });

    test('detects type mismatch in nested array with schema', () {
      final jsonString = json.encode({
        'status': 'ok',
        'data': {
          'items': [
            {'id': 1, 'label': 'Widget', 'price': 9999},
          ]
        }
      });

      expect(
        () => JsonDebugger.decode<NestedModel>(
          jsonString: jsonString,
          fromJson: NestedModel.fromJson,
          schema: {
            'status': String,
            'data': {
              'items': [
                {'id': int, 'label': String, 'price': String}
              ]
            }
          },
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.path,
          'path',
          r'$.data.items[0].price',
        )),
      );
    });

    test('detects mismatch in second array element', () {
      final jsonString = json.encode({
        'status': 'ok',
        'data': {
          'items': [
            {'id': 1, 'label': 'A', 'price': '100'},
            {'id': 2, 'label': 'B', 'price': 200}, // mismatch here
          ]
        }
      });

      expect(
        () => JsonDebugger.decode<NestedModel>(
          jsonString: jsonString,
          fromJson: NestedModel.fromJson,
          schema: {
            'status': String,
            'data': {
              'items': [
                {'id': int, 'label': String, 'price': String}
              ]
            }
          },
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.path,
          'path',
          r'$.data.items[1].price',
        )),
      );
    });

    test('succeeds without schema on valid data', () {
      final jsonString = '{"name": "Bob", "age": 25}';
      final result = JsonDebugger.decode<SimpleModel>(
        jsonString: jsonString,
        fromJson: SimpleModel.fromJson,
      );
      expect(result.name, 'Bob');
    });

    test('includes tag in error output', () {
      final jsonString = '{"name": 123, "age": 30}';
      try {
        JsonDebugger.decode<SimpleModel>(
          jsonString: jsonString,
          fromJson: SimpleModel.fromJson,
          schema: {'name': String},
          tag: 'MyTag',
        );
        fail('Should have thrown');
      } on JsonDebugError catch (e) {
        expect(e.tag, 'MyTag');
        expect(e.toString(), contains('[MyTag]'));
      }
    });
  });

  // ─── validate() tests ───────────────────────────────────────────

  group('JsonDebugger.validate()', () {
    test('returns empty list for valid JSON', () {
      final jsonMap = {'name': 'Alice', 'age': 30};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'name': String, 'age': int},
      );
      expect(errors, isEmpty);
    });

    test('returns errors for type mismatches', () {
      final jsonMap = {'name': 123, 'age': 'thirty'};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'name': String, 'age': int},
      );
      expect(errors, hasLength(2));
      expect(errors[0].path, r'$.name');
      expect(errors[1].path, r'$.age');
    });

    test('validates nested structures', () {
      final jsonMap = {
        'data': {
          'items': [
            {'id': 1, 'value': 'correct'},
            {'id': '2', 'value': 'also correct'}, // id should be int
          ]
        }
      };
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {
          'data': {
            'items': [
              {'id': int, 'value': String}
            ]
          }
        },
      );
      expect(errors, hasLength(1));
      expect(errors.first.path, r'$.data.items[1].id');
    });

    test('reports error when map expected but got other type', () {
      final jsonMap = {'data': 'not a map'};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {
          'data': {'key': String}
        },
      );
      expect(errors, hasLength(1));
      expect(errors.first.message, 'Expected a JSON object');
    });

    test('reports error when list expected but got other type', () {
      final jsonMap = {
        'items': 'not a list',
      };
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {
          'items': [String]
        },
      );
      expect(errors, hasLength(1));
      expect(errors.first.message, 'Expected a JSON array');
    });

    test('skips missing keys without error', () {
      final jsonMap = {'name': 'Alice'};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'name': String, 'age': int},
      );
      expect(errors, isEmpty);
    });

    test('allows null values (nullable by default)', () {
      final jsonMap = {'name': null};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'name': String},
      );
      expect(errors, isEmpty);
    });

    test('allows int where double is expected', () {
      final jsonMap = {'score': 42};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'score': double},
      );
      expect(errors, isEmpty);
    });

    test('catches bool where String expected', () {
      final jsonMap = {'flag': true};
      final errors = JsonDebugger.validate(
        json: jsonMap,
        schema: {'flag': String},
      );
      expect(errors, hasLength(1));
    });
  });

  // ─── wrap() tests ───────────────────────────────────────────────

  group('JsonDebugger.wrap()', () {
    test('succeeds with valid data', () {
      final jsonMap = {'name': 'Alice', 'age': 30};
      final result = JsonDebugger.wrap<SimpleModel>(
        deserialize: () => SimpleModel.fromJson(jsonMap),
        json: jsonMap,
      );
      expect(result.name, 'Alice');
    });

    test('catches deserialization failure and provides path info', () {
      final jsonMap = {
        'status': 'ok',
        'data': {
          'items': [
            {'id': 1, 'label': 'Widget', 'price': 9999},
          ]
        }
      };
      expect(
        () => JsonDebugger.wrap<NestedModel>(
          deserialize: () => NestedModel.fromJson(jsonMap),
          json: jsonMap,
          tag: 'NestedModel',
        ),
        throwsA(isA<JsonDebugError>().having(
          (e) => e.tag,
          'tag',
          'NestedModel',
        )),
      );
    });
  });

  // ─── JsonDebugError tests ───────────────────────────────────────

  group('JsonDebugError', () {
    test('toString includes all fields', () {
      final error = JsonDebugError(
        message: 'Type mismatch',
        path: r'$.data.items[0].price',
        expected: 'String',
        actual: 'int (value: 9999)',
        tag: 'TestModel',
      );
      final str = error.toString();
      expect(str, contains('Type mismatch'));
      expect(str, contains(r'$.data.items[0].price'));
      expect(str, contains('String'));
      expect(str, contains('int (value: 9999)'));
      expect(str, contains('[TestModel]'));
    });

    test('toString works without optional fields', () {
      final error = JsonDebugError(
        message: 'Something failed',
        path: r'$',
      );
      final str = error.toString();
      expect(str, contains('Something failed'));
      expect(str, isNot(contains('Expected:')));
      expect(str, isNot(contains('Actual:')));
    });

    test('toString includes suggestions', () {
      final error = JsonDebugError(
        message: 'Type mismatch',
        path: r'$',
        suggestions: ['Location A', 'Location B'],
      );
      final str = error.toString();
      expect(str, contains('Location A'));
      expect(str, contains('Location B'));
    });
  });
}
