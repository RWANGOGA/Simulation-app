/// Risk factors that an old record may still carry but no screen may show.
///
/// The triage score once included a term for the camera's SpO2 estimate. That
/// estimate is a perfusion proxy, not pulse oximetry: a number presented as an
/// oxygen saturation on a triage report invites decisions the measurement
/// cannot support. The scoring input has therefore been removed from the server
/// engine and from the offline engine alike.
///
/// Records written before the removal still hold the breakdown exactly as it
/// was computed, and that text stays in the device store and in the database —
/// it is the audit trail of what actually produced the score at the time, and
/// rewriting history would be its own kind of misrepresentation. What must not
/// happen is a present-day screen repeating it back as if it were current
/// clinical reasoning. So every widget that turns a stored explanation into
/// factors drops the retired ones through this one predicate.
///
/// The matched text is precisely what the old engines wrote (`SpO2 <value>%`,
/// from the server's `f"SpO2 {data.spo2}%"` and the Dart `'SpO2 ...%'`); the
/// subscript spelling is covered as well so a future typographic change in the
/// stored text cannot start leaking the value again.
library;

bool isRetiredRiskFactor(String label) {
  final head = label.trimLeft().toLowerCase();
  return head.startsWith('spo2') || head.startsWith('spo\u2082');
}
