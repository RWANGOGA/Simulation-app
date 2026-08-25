import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/network/api_client.dart';

void main() {
  group('PatientProfile demographics serialization', () {
    test('includes provided demographics with backend keys', () {
      final json = PatientProfile(
        age: 8,
        gender: 'Female',
        weight: 28.0,
        height: 130.0,
        fullName: 'Amara Nansubuga',
        dateOfBirth: DateTime.utc(2018, 3, 14),
        phone: '+256700123456',
        address: 'Plot 12, Kampala Road',
        nextOfKinName: 'Grace Nansubuga',
        nextOfKinPhone: '+256700654321',
        hospitalName: 'Mulago Hospital',
      ).toJson();

      expect(json['full_name'], 'Amara Nansubuga');
      expect(json['date_of_birth'], '2018-03-14');
      expect(json['phone'], '+256700123456');
      expect(json['address'], 'Plot 12, Kampala Road');
      expect(json['next_of_kin_name'], 'Grace Nansubuga');
      expect(json['next_of_kin_phone'], '+256700654321');
      expect(json['hospital_name'], 'Mulago Hospital');
    });

    test('omits blank demographics so anonymous walk-ins stay anonymous', () {
      final json = const PatientProfile(
        age: 30,
        gender: 'Male',
        weight: 70.0,
        height: 175.0,
        fullName: '   ',
        phone: '',
      ).toJson();

      expect(json.containsKey('full_name'), isFalse);
      expect(json.containsKey('phone'), isFalse);
      expect(json.containsKey('date_of_birth'), isFalse);
      expect(json['age'], 30);
    });
  });

  group('TriageResult demographics parsing', () {
    test('parses patient identity fields from the backend payload', () {
      final result = TriageResult.fromJson({
        'id': 1,
        'body_region': 'Head',
        'pain_type': 'throbbing',
        'severity': 6,
        'created_at': '2026-08-25T10:00:00',
        'patient_age': 8,
        'patient_name': 'Amara Nansubuga',
        'patient_date_of_birth': '2018-03-14',
        'patient_phone': '+256700123456',
        'patient_next_of_kin_name': 'Grace Nansubuga',
        'patient_next_of_kin_phone': '+256700654321',
        'patient_hospital_name': 'Mulago Hospital',
      });

      expect(result.patientName, 'Amara Nansubuga');
      expect(result.patientDateOfBirth, '2018-03-14');
      expect(result.patientPhone, '+256700123456');
      expect(result.patientNextOfKinName, 'Grace Nansubuga');
      expect(result.patientHospitalName, 'Mulago Hospital');
      // Older payloads without demographics still parse cleanly.
      expect(result.patientAddress, isNull);
    });
  });
}
