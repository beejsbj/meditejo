/// Why an update step stopped. The UI turns each into one plain sentence.
enum UpdateFailure {
  offline,
  rateLimited,
  unavailable,
  downloadFailed,
  hashMismatch,
  signatureMismatch,
  notMeditejo,
  installFailed,
}

class UpdateException implements Exception {
  const UpdateException(this.failure, [this.detail]);

  final UpdateFailure failure;
  final String? detail;

  @override
  String toString() =>
      'UpdateException(${failure.name}${detail == null ? '' : ': $detail'})';
}
