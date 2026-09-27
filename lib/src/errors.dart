import "types.dart";

class RustaBaseError implements Exception {
  RustaBaseError({
    this.message,
    this.url = "",
    this.status = 0,
    Json? data,
    this.cancelled = false,
    this.cause,
  }) : data = data ?? const {};

  final String? message;
  final String url;
  final int status;
  final Json data;
  final bool cancelled;
  final Object? cause;

  String get resolvedMessage =>
      message ??
      (data["message"] is String && (data["message"] as String).isNotEmpty
          ? data["message"] as String
          : cancelled
              ? "The request was cancelled."
              : status > 0
                  ? "Request failed with status $status."
                  : "Could not reach the RustaBase server.");

  Map<String, dynamic> get fieldErrors =>
      data["data"] is Map ? Map<String, dynamic>.from(data["data"] as Map) : {};

  factory RustaBaseError.from(Object error, {String url = ""}) {
    if (error is RustaBaseError) return error;
    return RustaBaseError(message: error.toString(), url: url, cause: error);
  }

  Json toJson() => {
        "name": "RustaBaseError",
        "message": resolvedMessage,
        "url": url,
        "status": status,
        "data": data,
        "cancelled": cancelled,
      };

  @override
  String toString() => "RustaBaseError: $resolvedMessage";
}
