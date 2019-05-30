module Postgrest.Internal.URL exposing (BaseURL(..), baseURLToString)


type BaseURL
    = BaseURL String


baseURLToString : BaseURL -> String
baseURLToString (BaseURL s) =
    s
