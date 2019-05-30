module Postgrest.Internal.JWT exposing (JWT(..), jwt, jwtHeader, jwtString)

import Http


type JWT
    = JWT String


jwt : String -> JWT
jwt =
    JWT


jwtString : JWT -> String
jwtString (JWT s) =
    s


jwtHeader : JWT -> Http.Header
jwtHeader (JWT jwt_) =
    Http.header "Authorization" <| "Bearer " ++ jwt_
