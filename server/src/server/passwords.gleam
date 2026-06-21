import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/result
import gleam/string

const iterations = 210_000

const dk_length = 64

const salt_length = 16

pub fn hash(password: String) -> String {
  let salt = crypto.strong_random_bytes(salt_length)
  encode(salt, stretch(password, salt, iterations))
}

pub fn verify(password: String, encoded: String) -> Bool {
  case decode(encoded) {
    Ok(#(iters, salt, expected)) ->
      crypto.secure_compare(stretch(password, salt, iters), expected)
    Error(_) -> False
  }
}

fn stretch(password: String, salt: BitArray, iters: Int) -> BitArray {
  pbkdf2(bit_array.from_string(password), salt, iters, dk_length)
}

fn encode(salt: BitArray, dk: BitArray) -> String {
  string.join(
    [
      "pbkdf2_sha512",
      int.to_string(iterations),
      bit_array.base16_encode(salt),
      bit_array.base16_encode(dk),
    ],
    "$",
  )
}

fn decode(encoded: String) -> Result(#(Int, BitArray, BitArray), Nil) {
  case string.split(encoded, "$") {
    ["pbkdf2_sha512", iters, salt, dk] -> {
      use iters <- result.try(int.parse(iters))
      use salt <- result.try(bit_array.base16_decode(salt))
      use dk <- result.try(bit_array.base16_decode(dk))
      Ok(#(iters, salt, dk))
    }
    _ -> Error(Nil)
  }
}

@external(erlang, "npwd_pbkdf2", "derive")
fn pbkdf2(
  password: BitArray,
  salt: BitArray,
  iterations: Int,
  length: Int,
) -> BitArray
