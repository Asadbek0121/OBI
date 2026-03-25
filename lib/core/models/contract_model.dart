class Contract {
  final String id;
  final String name;
  final String companyName; 
  final String ourOrganization; 
  final String? fileUrl; 
  final String? localPath; 
  final String status;
  final DateTime createdAt;

  Contract({
    required this.id,
    required this.name,
    required this.companyName,
    required this.ourOrganization,
    this.fileUrl,
    this.localPath,
    required this.status,
    required this.createdAt,
  });

  factory Contract.fromJson(Map<String, dynamic> json) {
    return Contract(
      id: json['id'],
      name: json['name'],
      companyName: json['company_name'] ?? 'Noma\'lum',
      ourOrganization: json['our_organization'] ?? 'Noma\'lum tashkilot',
      fileUrl: json['file_url'],
      localPath: json['local_path'],
      status: json['status'] ?? 'synced',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'company_name': companyName,
      'our_organization': ourOrganization,
      'file_url': fileUrl,
      'local_path': localPath,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Contract copyWith({
    String? localPath,
    String? fileUrl,
    String? status,
    String? companyName,
    String? ourOrganization,
  }) {
    return Contract(
      id: id,
      name: name,
      companyName: companyName ?? this.companyName,
      ourOrganization: ourOrganization ?? this.ourOrganization,
      fileUrl: fileUrl ?? this.fileUrl,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
