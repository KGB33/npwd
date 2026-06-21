-module(npwd_pbkdf2).
-export([derive/4]).

derive(Password, Salt, Iterations, Length) ->
    crypto:pbkdf2_hmac(sha512, Password, Salt, Iterations, Length).
