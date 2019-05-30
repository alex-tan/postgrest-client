module Postgrest.Internal.Endpoint exposing
    ( Endpoint(..)
    , EndpointOptions
    , decoder
    , defaultParams
    , url
    )

import Json.Decode exposing (Decoder)
import Postgrest.Internal.Params exposing (ColumnOrder, Params, Selectable, order, select)
import Postgrest.Internal.URL exposing (BaseURL)


type Endpoint record
    = Endpoint (EndpointOptions record)


type alias EndpointOptions record =
    { url : BaseURL
    , decoder : Decoder record
    , defaultSelect : Maybe (List Selectable)
    , defaultOrder : Maybe (List ColumnOrder)
    }


defaultParams : Endpoint r -> Params
defaultParams (Endpoint { defaultSelect, defaultOrder }) =
    [ defaultSelect |> Maybe.map select
    , defaultOrder |> Maybe.map order
    ]
        |> List.filterMap identity


decoder : Endpoint r -> Decoder r
decoder (Endpoint o) =
    o.decoder


url : Endpoint r -> BaseURL
url (Endpoint o) =
    o.url
