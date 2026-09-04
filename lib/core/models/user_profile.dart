/// User profile model mapped to the `profiles` Supabase table.
class UserProfile {
  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? nationalId;
  final String status; // PENDING_APPROVAL | APPROVED | REJECTED | SUSPENDED | INACTIVE
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.nationalId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      nationalId: json['national_id'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'email': email,
        'national_id': nationalId,
        'status': status,
      };

  bool get isApproved => status == 'APPROVED';
  bool get isPending => status == 'PENDING_APPROVAL';
  bool get isRejected => status == 'REJECTED';
  bool get isSuspended => status == 'SUSPENDED';
}
