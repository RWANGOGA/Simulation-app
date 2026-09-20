import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/storage/doctor_draft.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/network/api_client.dart';

void main() {
  group('DoctorDraft', () {
    test('hash produces consistent output for same input', () {
      const password = 'TestPass123';
      final hash1 = DoctorDraft.hash(password);
      final hash2 = DoctorDraft.hash(password);
      expect(hash1, hash2);
    });

    test('hash produces different output for different input', () {
      final hash1 = DoctorDraft.hash('Password1');
      final hash2 = DoctorDraft.hash('Password2');
      expect(hash1, isNot(hash2));
    });

    test('verifyPassword returns true for correct password', () {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('Secret123'),
      );

      expect(draft.verifyPassword('Secret123'), isTrue);
    });

    test('verifyPassword returns false for incorrect password', () {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('Secret123'),
      );

      expect(draft.verifyPassword('WrongPass'), isFalse);
    });

    test('createOffline generates negative localId', () {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: 'hash',
      );

      expect(draft.localId, lessThan(0));
      expect(draft.isSynced, isFalse);
      expect(draft.doctorId, isNull);
    });

    test('fromSynced creates synced draft with positive localId', () {
      final draft = DoctorDraft.fromSynced(
        doctorId: 42,
        profile: Doctor(
          id: 42,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 1),
      );

      expect(draft.localId, 42);
      expect(draft.doctorId, 42);
      expect(draft.isSynced, isTrue);
    });

    test('copyWith updates only specified fields', () {
      final original = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: 'hash',
      );

      final updated = original.copyWith(isSynced: true, doctorId: 100);

      expect(updated.isSynced, isTrue);
      expect(updated.doctorId, 100);
      expect(updated.localId, original.localId);
      expect(updated.passwordHash, original.passwordHash);
    });

    test('toJson and fromJson round-trip preserves data', () {
      final original = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
          role: 'Doctor',
          licenseNumber: 'LIC123',
          phone: '+1234567890',
          hospitalName: 'Test Hospital',
        ),
        passwordHash: DoctorDraft.hash('Secret123'),
      );

      final json = original.toJson();
      final restored = DoctorDraft.fromJson(json);

      expect(restored.localId, original.localId);
      expect(restored.doctorId, original.doctorId);
      expect(restored.isSynced, original.isSynced);
      expect(restored.passwordHash, original.passwordHash);
      expect(restored.profile.email, original.profile.email);
      expect(restored.profile.fullName, original.profile.fullName);
      expect(restored.profile.role, original.profile.role);
      expect(restored.profile.licenseNumber, original.profile.licenseNumber);
      expect(restored.profile.phone, original.profile.phone);
      expect(restored.profile.hospitalName, original.profile.hospitalName);
      expect(restored.savedAt, original.savedAt);
    });
  });

  group('PatientProfile', () {
    test('toJson includes all non-empty optional fields', () {
      final profile = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
        fullName: 'Jane Doe',
        dateOfBirth: DateTime(1994, 5, 15),
        phone: '+1234567890',
        address: '123 Main St',
        nextOfKinName: 'John Doe',
        nextOfKinPhone: '+1987654321',
        hospitalName: 'General Hospital',
      );

      final json = profile.toJson();

      expect(json['age'], 30);
      expect(json['gender'], 'Female');
      expect(json['weight'], 70.0);
      expect(json['height'], 165.0);
      expect(json['full_name'], 'Jane Doe');
      expect(json['date_of_birth'], '1994-05-15');
      expect(json['phone'], '+1234567890');
      expect(json['address'], '123 Main St');
      expect(json['next_of_kin_name'], 'John Doe');
      expect(json['next_of_kin_phone'], '+1987654321');
      expect(json['hospital_name'], 'General Hospital');
    });

    test('toJson omits empty optional fields', () {
      final profile = const PatientProfile(
        age: 30,
        gender: 'Male',
        weight: 70.0,
        height: 175.0,
        fullName: '   ',
        phone: '',
      );

      final json = profile.toJson();

      expect(json.containsKey('full_name'), isFalse);
      expect(json.containsKey('phone'), isFalse);
      expect(json.containsKey('date_of_birth'), isFalse);
      expect(json.containsKey('address'), isFalse);
    });

    test('fromJson parses all fields correctly', () {
      final json = {
        'age': 25,
        'gender': 'Female',
        'weight': 60.0,
        'height': 160.0,
        'full_name': 'Alice Smith',
        'date_of_birth': '1999-08-20',
        'phone': '+15551234567',
        'address': '456 Oak Ave',
        'next_of_kin_name': 'Bob Smith',
        'next_of_kin_phone': '+15557654321',
        'hospital_name': 'City Hospital',
      };

      final profile = PatientProfile.fromJson(json);

      expect(profile.age, 25);
      expect(profile.gender, 'Female');
      expect(profile.weight, 60.0);
      expect(profile.height, 160.0);
      expect(profile.fullName, 'Alice Smith');
      expect(profile.dateOfBirth, DateTime(1999, 8, 20));
      expect(profile.phone, '+15551234567');
      expect(profile.address, '456 Oak Ave');
      expect(profile.nextOfKinName, 'Bob Smith');
      expect(profile.nextOfKinPhone, '+15557654321');
      expect(profile.hospitalName, 'City Hospital');
    });
  });

  group('Doctor', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 1,
        'email': 'doc@example.com',
        'full_name': 'Dr. Smith',
        'is_active': true,
        'role': 'Doctor',
        'license_number': 'MED12345',
        'phone': '+15551112222',
        'hospital_name': 'Medical Center',
      };

      final doctor = Doctor.fromJson(json);

      expect(doctor.id, 1);
      expect(doctor.email, 'doc@example.com');
      expect(doctor.fullName, 'Dr. Smith');
      expect(doctor.isActive, isTrue);
      expect(doctor.role, 'Doctor');
      expect(doctor.licenseNumber, 'MED12345');
      expect(doctor.phone, '+15551112222');
      expect(doctor.hospitalName, 'Medical Center');
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 2,
        'email': 'nurse@example.com',
        'full_name': 'Nurse Jane',
        'is_active': true,
      };

      final doctor = Doctor.fromJson(json);

      expect(doctor.id, 2);
      expect(doctor.email, 'nurse@example.com');
      expect(doctor.fullName, 'Nurse Jane');
      expect(doctor.isActive, isTrue);
      expect(doctor.role, isNull);
      expect(doctor.licenseNumber, isNull);
      expect(doctor.phone, isNull);
      expect(doctor.hospitalName, isNull);
    });
  });
}