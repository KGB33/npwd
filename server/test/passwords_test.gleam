import gleam/string
import server/passwords

pub fn hash_then_verify_test() {
  let encoded = passwords.hash("correct horse")
  assert passwords.verify("correct horse", encoded)
  assert !passwords.verify("wrong horse", encoded)
}

pub fn salts_are_unique_test() {
  assert passwords.hash("same") != passwords.hash("same")
}

pub fn garbage_hash_does_not_verify_test() {
  assert !passwords.verify("anything", "not-a-real-hash")
}

pub fn dummy_verify_runs_test() {
  assert passwords.dummy_verify("anything") == Nil
}

pub fn ordinary_password_is_within_limit_test() {
  assert passwords.within_limit("correct horse battery staple")
}

pub fn oversized_password_is_rejected_test() {
  assert !passwords.within_limit(string.repeat("a", 1025))
}

pub fn limit_boundary_is_accepted_test() {
  assert passwords.within_limit(string.repeat("a", 1024))
}
