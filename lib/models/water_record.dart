import 'dart:convert';

/// Registro individual de consumo de agua.
///
/// La cantidad canónica es [amountMl] en mililitros.
/// El total de un día se deriva de la suma de los registros vigentes,
/// no de un acumulador independiente que pueda desviarse.
class WaterRecord {
  final String id;           // UUID generado en cliente
  final String uid;          // propietario (UID de Firebase Auth)
  final int amountMl;        // cantidad en mililitros (> 0)
  final DateTime recordedAt; // momento del consumo
  final DateTime createdAt;
  final DateTime updatedAt;

  const WaterRecord({
    required this.id,
    required this.uid,
    required this.amountMl,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  WaterRecord copyWith({
    int?      amountMl,
    DateTime? recordedAt,
    DateTime? updatedAt,
  }) => WaterRecord(
    id:         id,
    uid:        uid,
    amountMl:   amountMl   ?? this.amountMl,
    recordedAt: recordedAt ?? this.recordedAt,
    createdAt:  createdAt,
    updatedAt:  updatedAt  ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id':         id,
    'uid':        uid,
    'ml':         amountMl,
    'recordedAt': recordedAt.toIso8601String(),
    'createdAt':  createdAt.toIso8601String(),
    'updatedAt':  updatedAt.toIso8601String(),
  };

  factory WaterRecord.fromMap(Map<String, dynamic> m) => WaterRecord(
    id:         m['id'] as String,
    uid:        m['uid'] as String,
    amountMl:   m['ml'] as int,
    recordedAt: DateTime.parse(m['recordedAt'] as String),
    createdAt:  DateTime.parse(m['createdAt'] as String),
    updatedAt:  DateTime.parse(m['updatedAt'] as String),
  );

  String toJson() => jsonEncode(toMap());
  factory WaterRecord.fromJson(String s) => WaterRecord.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
