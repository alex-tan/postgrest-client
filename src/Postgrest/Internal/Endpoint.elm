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


type Endpoint a
    = Endpoint (EndpointOptions a)


type alias EndpointOptions a =
    { url : BaseURL
    , decoder : Decoder a
    , defaultSelect : Maybe (List Selectable)
    , defaultOrder : Maybe (List ColumnOrder)
    }


defaultParams : Endpoint a -> Params
defaultParams (Endpoint { defaultSelect, defaultOrder }) =
    [ defaultSelect |> Maybe.map select
    , defaultOrder |> Maybe.map order
    ]
        |> List.filterMap identity


decoder : Endpoint a -> Decoder a
decoder (Endpoint o) =
    o.decoder


url : Endpoint a -> BaseURL
url (Endpoint o) =
    o.url
