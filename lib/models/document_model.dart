class DocumentRecord {
  final String id;
  final String branchCode;
  final String title;
  final String description;
  final String fileUrl;
  final DateTime createdAt;

  DocumentRecord({
    required this.id,
    required this.branchCode,
    required this.title,
    required this.description,
    required this.fileUrl,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'title': title,
    'description': description,
    'file_url': fileUrl,
    'created_at': createdAt.toIso8601String(),
  };

  factory DocumentRecord.fromJson(Map<String, dynamic> json) => DocumentRecord(
    id: json['id'],
    branchCode: json['branch_code'],
    title: json['title'],
    description: json['description'],
    fileUrl: json['file_url'],
    createdAt: DateTime.parse(json['created_at']),
  );
}
