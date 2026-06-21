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
