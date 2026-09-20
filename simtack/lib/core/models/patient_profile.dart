/// Patient demographic profile — mirrors the backend schema.
/// Used for both API requests and local offline drafts.
class PatientProfile {
  final int age;
  final String gender;
  final double weight;
  final double height;
  // Optional personal demographics — the flow stays fast for anonymous
  // walk-ins, but anything provided is stored and carried onto the
  // clinical report / QR-scan lookup.
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? phone;
  final String? address;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? hospitalName;

  const PatientProfile({
    required this.age,
    required this.gender,
    required this.weight,
    required this.height,
    this.fullName,
    this.dateOfBirth,
    this.phone,
    this.address,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.hospitalName,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight': weight,
        'height': height,
        if (fullName != null && fullName!.trim().isNotEmpty)
          'full_name': fullName!.trim(),
        if (dateOfBirth != null)
          'date_of_birth': '${dateOfBirth!.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth!.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth!.day.toString().padLeft(2, '0')}',
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
        if (address != null && address!.trim().isNotEmpty)
          'address': address!.trim(),
        if (nextOfKinName != null && nextOfKinName!.trim().isNotEmpty)
          'next_of_kin_name': nextOfKinName!.trim(),
        if (nextOfKinPhone != null && nextOfKinPhone!.trim().isNotEmpty)
          'next_of_kin_phone': nextOfKinPhone!.trim(),
        if (hospitalName != null && hospitalName!.trim().isNotEmpty)
          'hospital_name': hospitalName!.trim(),
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        age: json['age'] as int,
        gender: json['gender'] as String,
        weight: (json['weight'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        fullName: json['full_name'] as String?,
        dateOfBirth: json['date_of_birth'] != null
            ? DateTime.parse(json['date_of_birth'] as String)
            : null,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        nextOfKinName: json['next_of_kin_name'] as String?,
        nextOfKinPhone: json['next_of_kin_phone'] as String?,
        hospitalName: json['hospital_name'] as String?,
      );
}