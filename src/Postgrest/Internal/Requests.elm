module Postgrest.Internal.Requests exposing
    ( Request(..)
    , RequestType(..)
    , defaultRequest
    , mapRequest
    , requestToURL
    , requestTypeToBody
    , requestTypeToHTTPMethod
    , requestTypeToHeaders
    , setMandatoryParams
    )

import Http
import Json.Decode exposing (Decoder)
import Json.Encode as JE
import Postgrest.Internal.Endpoint as Endpoint exposing (Endpoint)
import Postgrest.Internal.JWT exposing (JWT, jwtHeader)
import Postgrest.Internal.Params exposing (Params, concatParams, toQueryString)
import Postgrest.Internal.URL exposing (BaseURL, baseURLToString)


type Request r
    = Request (RequestOptions r)


type alias RequestOptions r =
    { options : RequestType r
    , timeout : Maybe Float
    , defaultParams : Params
    , overrideParams : Params
    , mandatoryParams : Params
    , baseURL : BaseURL
    }


type RequestType r
    = Post JE.Value (Decoder r)
    | Patch JE.Value (Decoder r)
    | Get (Decoder r)
    | Delete r


defaultRequest : Endpoint r -> RequestType returning -> Request returning
defaultRequest e requestType =
    Request
        { options = requestType
        , timeout = Nothing
        , defaultParams = Endpoint.defaultParams e
        , overrideParams = []
        , mandatoryParams = []
        , baseURL = Endpoint.url e
        }


requestTypeToHeaders : JWT -> RequestType r -> List Http.Header
requestTypeToHeaders jwt_ r =
    case r of
        Post body decoder ->
            [ jwtHeader jwt_, returnRepresentationHeader ]

        Patch body decoder ->
            [ jwtHeader jwt_, returnRepresentationHeader ]

        Get decoder ->
            [ jwtHeader jwt_ ]

        Delete returning ->
            [ jwtHeader jwt_ ]


requestTypeToBody : RequestType r -> Http.Body
requestTypeToBody r =
    case r of
        Delete _ ->
            Http.emptyBody

        Get _ ->
            Http.emptyBody

        Post body _ ->
            Http.jsonBody body

        Patch body _ ->
            Http.jsonBody body


requestTypeToHTTPMethod : RequestType r -> String
requestTypeToHTTPMethod r =
    case r of
        Post _ _ ->
            "POST"

        Patch _ _ ->
            "PATCH"

        Delete _ ->
            "DELETE"

        Get _ ->
            "GET"


setMandatoryParams : Params -> Request r -> Request r
setMandatoryParams p =
    mapRequest (\req -> { req | mandatoryParams = p })


returnRepresentationHeader : Http.Header
returnRepresentationHeader =
    Http.header "Prefer" "return=representation"


mapRequest : (RequestOptions r -> RequestOptions r) -> Request r -> Request r
mapRequest f (Request options) =
    Request (f options)


requestToURL : RequestOptions r -> String
requestToURL { defaultParams, overrideParams, mandatoryParams, baseURL } =
    let
        params =
            concatParams [ defaultParams, overrideParams, mandatoryParams ]
    in
    [ baseURLToString baseURL, toQueryString params ]
        |> List.filter (String.isEmpty >> Basics.not)
        |> String.join "?"
