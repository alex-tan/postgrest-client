module Postgrest.Client exposing
    ( Endpoint
    , Request
    , endpoint
    , customEndpoint
    , getMany
    , postOne
    , getByPrimaryKey
    , patchByPrimaryKey
    , deleteByPrimaryKey
    , setParams
    , get
    , post
    , unsafePatch
    , JWT, jwt, jwtString
    , toCmd, toTask
    , PrimaryKey
    , primaryKey
    , primaryKey2
    , primaryKey3
    , Error(..), toHttpError
    , Param
    , Params
    , Selectable
    , ColumnOrder
    , Value
    , Operator
    , select
    , allAttributes
    , attribute
    , attributes
    , resource
    , resourceWithParams
    , combineParams
    , concatParams
    , normalizeParams
    , toQueryString
    , param
    , or
    , and
    , nestedParam
    , eq
    , gt
    , gte
    , inList
    , limit
    , lt
    , lte
    , neq
    , not
    , true
    , false
    , null
    , value
    , offset
    , ilike
    , like
    , string
    , int
    , list
    , order
    , asc
    , desc
    , nullsfirst
    , nullslast
    , plfts
    , phfts
    , fts
    , getOne
    )

{-|


# Request Construction and Modification

@docs Endpoint
@docs Request
@docs endpoint
@docs customEndpoint
@docs getMany
@docs postOne
@docs getByPrimaryKey
@docs patchByPrimaryKey
@docs deleteByPrimaryKey
@docs setParams


# Generic Requests

@docs get
@docs post
@docs unsafePatch
@docs unsafeDelete


# Request Authentication

@docs JWT, jwt, jwtString


# Execution

@docs toCmd, toTask


# Primary Keys

@docs PrimaryKey
@docs primaryKey
@docs primaryKey2
@docs primaryKey3


# Errors

@docs Error, toHttpError


# URL Parameter Construction

@docs Param
@docs Params
@docs Selectable
@docs ColumnOrder
@docs Value
@docs Operator


## Select

@docs select
@docs allAttributes
@docs attribute
@docs attributes
@docs resource
@docs resourceWithParams


## Converting/combining into something usable

@docs combineParams
@docs concatParams
@docs normalizeParams
@docs toQueryString


## Param

@docs param
@docs or
@docs and
@docs nestedParam


## Operators

@docs eq
@docs gt
@docs gte
@docs inList
@docs limit
@docs lt
@docs lte
@docs neq
@docs not
@docs true
@docs false
@docs null
@docs value
@docs offset
@docs ilike
@docs like


## Values

@docs string
@docs int
@docs list


## Order

@docs order
@docs asc
@docs desc
@docs nullsfirst
@docs nullslast


## Full-Text Search

@docs plfts
@docs phfts
@docs fts

-}

import Dict exposing (Dict)
import Http exposing (Resolver, header, task)
import Json.Decode as JD exposing (Decoder, decodeString, field, index, list, map, map4, maybe)
import Json.Encode as JE
import Postgrest.Internal.Endpoint as Endpoint exposing (Endpoint(..), EndpointOptions)
import Postgrest.Internal.JWT as JWT exposing (JWT)
import Postgrest.Internal.Params as Param exposing (ColumnOrder(..), Language, NullOption(..), Operator(..), Param(..), Selectable(..), Value(..))
import Postgrest.Internal.Requests as Request exposing (..)
import Postgrest.Internal.URL exposing (BaseURL(..))
import Task exposing (Task)
import Url


{-| Negate a condition.

    [ param "my_tsv" <| not <| phfts (Just "english") "The Fat Cats"
    ]
    |> toQueryString
    -- my_tsv=not.phfts(english).The%20Fat%20Cats

-}
not : Operator -> Operator
not =
    Not


{-| Join multiple conditions together with or.

    [ or
        [ param "age" <| gte <| int 14
        , param "age" <| lte <| int 18
        ]
    ]
    |> toQueryString

    -- or=(age.gte.14,age.lte.18)

-}
or : List Param -> Param
or =
    Or


{-| Join multiple conditions together with and.

    [ and
        [ param "grade" <| gte <| int 90
        , param "student" <| true
        , or
            [ param "age" <| gte <| int 14
            , param "age" <| null
            ]
        ]
    ]
    |> toQueryString

    -- and=(grade.gte.90,student.is.true,or(age.gte.14,age.is.null))

-}
and : List Param -> Param
and =
    And


{-| A constructor for an individual postgrest parameter.

    param "name" (eq (string "John"))

-}
param : String -> Operator -> Param
param =
    Param


{-| A constructor for the limit parameter.

    limit 10

-}
limit : Int -> Param
limit =
    Limit


{-| Offset
-}
offset : Int -> Param
offset =
    Offset


{-| Normalize a string into a postgrest value.
-}
string : String -> Value
string =
    String


{-| Normalize an int into a postgrest value.
-}
int : Int -> Value
int =
    Int


{-| Sort so that nulls will come first.

    order [ asc "age" |> nullsfirst ]

-}
nullsfirst : ColumnOrder -> ColumnOrder
nullsfirst o =
    case o of
        Asc s _ ->
            Asc s (Just NullsFirst)

        Desc s _ ->
            Desc s (Just NullsFirst)


{-| Sort so that nulls will come last.

    order [ asc "age" |> nullslast ]

-}
nullslast : ColumnOrder -> ColumnOrder
nullslast o =
    case o of
        Asc s _ ->
            Asc s (Just NullsLast)

        Desc s _ ->
            Desc s (Just NullsLast)


{-| Used in combination with `order` to sort results ascending.
-}
asc : String -> ColumnOrder
asc s =
    Asc s Nothing


{-| Used in combination with `order` to sort results descending.
-}
desc : String -> ColumnOrder
desc s =
    Desc s Nothing


{-| LIKE operator (use \* in place of %)

    param "text" <| like "foo*bar"

-}
like : String -> Operator
like =
    Like


{-| ILIKE operator (use \* in place of %)

    param "text" <| ilike "foo*bar"

-}
ilike : String -> Operator
ilike =
    Ilike


{-| When a value needs to be null

    param "age" <| null

-}
null : Operator
null =
    Null


{-| Full-Text Search using to\_tsquery

    [ param "my_tsv" <| fts (Just "french") "amusant" ]
        |> toQueryString

    "my_tsv=fts(french).amusant"

-}
fts : Maybe Language -> String -> Operator
fts =
    Fts


{-| Full-Text Search using plainto\_tsquery
-}
plfts : Maybe Language -> String -> Operator
plfts =
    Plfts


{-| Full-Text Search using phraseto\_tsquery
-}
phfts : Maybe Language -> String -> Operator
phfts =
    Phfts


{-| Used to indicate you need a column to be equal to a certain value.
-}
eq : Value -> Operator
eq =
    Eq


{-| Used to indicate you need a column to be not equal to a certain value.
-}
neq : Value -> Operator
neq =
    Neq


{-| Used to indicate you need a column to be less than a certain value.
-}
lt : Value -> Operator
lt =
    Param.LT


{-| Used to indicate you need a column to be greater than a certain value.
-}
gt : Value -> Operator
gt =
    Param.GT


{-| Used to indicate you need a column to be less than or equal than a certain value.
-}
lte : Value -> Operator
lte =
    LTE


{-| Used to indicate you need a column to be greater than or equal than a certain value.
-}
gte : Value -> Operator
gte =
    GTE


{-| Used to indicate you need a column to be within a certain list of values.

    param "name" <| inList string [ "Chico", "Harpo", "Groucho" ]

    -- name=in.(\"Chico\",\"Harpo\",\"Groucho\")"

-}
inList : (a -> Value) -> List a -> Operator
inList toValue l =
    In <| List <| List.map toValue l


{-| When you don't want to use a specific type after the equals sign in the query, you
can use `value` to set anything you want.
-}
value : Value -> Operator
value =
    Value


{-| When you need a column value to be true

    -- foo=is.true
    [ P.param "foo" P.true ]
        |> toQueryString

-}
true : Operator
true =
    Param.True


{-| When you need a column value to be false

    -- foo=is.false
    [ P.param "foo" P.false ]
        |> toQueryString

-}
false : Operator
false =
    Param.False


{-| When you want to select a certain column.
-}
attribute : String -> Selectable
attribute =
    Param.Attribute


{-| When you want to select a nested resource with no special parameters for the nested
resources. If you do want to specify parameters, see `resourceWithParams`.
-}
resource : String -> List Selectable -> Selectable
resource name selectable =
    Resource name [] selectable


{-| A constructor for the limit parameter.

    order (asc "name")

    order (desc "name")

-}
order : List ColumnOrder -> Param
order =
    Param.order


{-| A constructor for the select parameter.

    P.select
        [ P.attribute "id"
        , P.attribute "title"
        , P.resource "user" <|
            P.attributes
                [ "email"
                , "name"
                ]
        ]

-}
select : List Selectable -> Param
select =
    Param.select


{-| When you want to specify an operator for a nested resource manually.
It is recommended to use resourceWithParams though.

    [ select
        [ attribute "*"
        , resource "actors" allAttributes
        ]
    , nestedParam [ "actors" ] <| limit 10
    , nestedParam [ "actors" ] <| offset 2
    ]
    |> toQueryString
    -- "select=*,actors(*)&actors.limit=10&actors.offset=2"

-}
nestedParam : List String -> Param -> Param
nestedParam =
    Param.nestedParam


{-| Takes Params and returns a query string such as
`foo=eq.bar&baz=is.true`
-}
toQueryString : Params -> String
toQueryString =
    Param.toQueryString


{-| When you want to select a nested resource with special praameters.

    [ P.select
        [ P.resource "sites"
            [ P.resourceWithParams "streams"
                [ P.order [ P.asc "name" ]
                ]
                allAttributes
            ]
        ]
    ]
        |> toQueryString

    -- select=sites(streams(*))&sites.streams.order=name.asc

-}
resourceWithParams : String -> Params -> List Selectable -> Selectable
resourceWithParams =
    Resource


{-| This is available if you need it, but more likely you'll want to use
`inList`.
-}
list : List Value -> Value
list values =
    List values


{-| Shorthand for attributes, when you don't need to specify nested resources:

    -- Short version
    attributes [ "id" "name" ]

    -- Long version
    [ attribute "id"
    , attribute "name"
    ]

-}
attributes : List String -> List Selectable
attributes =
    List.map Attribute


{-| When you want to select all attributes. This is only useful when used
to select attributes of a resource or override default parameters in another function
since postgrest returns all attributes by default.
-}
allAttributes : List Selectable
allAttributes =
    attributes [ "*" ]


setParams : Params -> Request r -> Request r
setParams p =
    mapRequest (\req -> { req | overrideParams = p })


{-| Takes Params and returns the parameters as a list of (Key, Value) strings.
-}
normalizeParams : Params -> List ( String, String )
normalizeParams =
    Param.normalizeParams


{-| Takes a list of Params and combines them, preferring the last sets first.
-}
concatParams : List Params -> Params
concatParams =
    Param.concatParams


{-| Takes a default set of params and a custom set of params and prefers the second set.
Useful when you're constructing reusable functions that make similar queries.
-}
combineParams : Params -> Params -> Params
combineParams =
    Param.combineParams


{-| A type that represents the operator of a query. In `name=eq.John` the operator would be the `=`.
-}
type alias Operator =
    Param.Operator


{-| Type that can be represented in the queries: strings, ints and lists.
-}
type alias Value =
    Param.Value


{-| A type to specify whether you want an order to be ascending or descending, and
optionally whether you want nulls to be first or last.
-}
type alias ColumnOrder =
    Param.ColumnOrder


{-| A type representing which attributes and resources you want to select.
It also contains parameters that target nested resources.
-}
type alias Selectable =
    Param.Selectable


{-| A list of Param.
-}
type alias Params =
    Param.Params


{-| An individual postgrest parameter.
-}
type alias Param =
    Param.Param


getMany : Endpoint r -> Request (List r)
getMany e =
    defaultRequest e <| Get <| JD.list <| Endpoint.decoder e


getOne : Endpoint r -> Request r
getOne e =
    defaultRequest e <| Get <| JD.index 0 <| Endpoint.decoder e


type alias GetOptions a =
    { params : Params
    , decoder : Decoder a
    }


get : String -> GetOptions a -> Request a
get baseURL { params, decoder } =
    Request
        { options = Get decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        }


type alias PostOptions a =
    { params : Params
    , decoder : Decoder a
    , body : JE.Value
    }


post : String -> PostOptions a -> Request a
post baseURL { params, decoder, body } =
    Request
        { options = Post body decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        }


type alias UnsafePatchOptions a =
    { body : JE.Value
    , decoder : Decoder a
    , params : Params
    }


unsafePatch : String -> UnsafePatchOptions a -> Request a
unsafePatch baseURL { body, decoder, params } =
    Request
        { options = Patch body decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        }


type alias UnsafeDeleteOptions a =
    { params : Params
    , returning : a
    }


unsafeDelete : String -> UnsafeDeleteOptions a -> Request a
unsafeDelete url { returning, params } =
    Request
        { options = Delete returning
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL url
        }


primaryKeyEqClause : PrimaryKey primaryKey -> primaryKey -> Params
primaryKeyEqClause converter pk =
    let
        pkPartToParam ( key, toParam ) =
            param key <| eq <| toParam pk

        targetCondition =
            case converter of
                PrimaryKey [ a ] ->
                    pkPartToParam a

                PrimaryKey xs ->
                    xs
                        |> List.map pkPartToParam
                        |> and
    in
    [ targetCondition
    , limit 1
    ]


getByPrimaryKey : Endpoint r -> PrimaryKey p -> p -> Request r
getByPrimaryKey e primaryKeyToParams_ primaryKey_ =
    defaultRequest e (Get <| index 0 <| Endpoint.decoder e)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams_ primaryKey_)


patchByPrimaryKey : Endpoint record -> PrimaryKey pk -> pk -> JE.Value -> Request record
patchByPrimaryKey e primaryKeyToParams primaryKey_ body =
    defaultRequest e (Patch body <| index 0 <| Endpoint.decoder e)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams primaryKey_)


deleteByPrimaryKey : Endpoint r -> PrimaryKey p -> p -> Request p
deleteByPrimaryKey e primaryKeyToParams primaryKey_ =
    defaultRequest e (Delete primaryKey_)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams primaryKey_)


postOne : Endpoint r -> JE.Value -> Request r
postOne e body =
    defaultRequest e <| Post body <| index 0 <| Endpoint.decoder e


toCmd : JWT -> (Result Error r -> msg) -> Request r -> Cmd msg
toCmd jwt_ toMsg (Request options) =
    Http.request
        { method = requestTypeToHTTPMethod options.options
        , headers = requestTypeToHeaders jwt_ options.options
        , url = requestToURL options
        , body = requestTypeToBody options.options
        , timeout = options.timeout
        , tracker = Nothing
        , expect =
            case options.options of
                Delete returning ->
                    expectWhatever (toMsg << Result.map (always returning))

                Get decoder ->
                    expectJson toMsg decoder

                Post _ decoder ->
                    expectJson toMsg decoder

                Patch _ decoder ->
                    expectJson toMsg decoder
        }


toTask : JWT -> Request r -> Task Error r
toTask jwt_ (Request o) =
    let
        { options } =
            o
    in
    task
        { body = requestTypeToBody options
        , timeout = o.timeout
        , url = requestToURL o
        , method = requestTypeToHTTPMethod options
        , headers = requestTypeToHeaders jwt_ options
        , resolver =
            case options of
                Delete returning ->
                    Http.stringResolver <| always <| Ok returning

                Get decoder ->
                    jsonResolver decoder

                Post body decoder ->
                    jsonResolver decoder

                Patch body decoder ->
                    jsonResolver decoder
        }


jsonResolver : Decoder a -> Resolver Error a
jsonResolver =
    Http.stringResolver << resolution


resolution : Decoder a -> Http.Response String -> Result Error a
resolution decoder response =
    case response of
        Http.BadUrl_ url_ ->
            Err <| BadUrl url_

        Http.Timeout_ ->
            Err Timeout

        Http.NetworkError_ ->
            Err NetworkError

        Http.BadStatus_ metadata body ->
            Err <| badStatusBodyToPostgrestError metadata.statusCode body

        Http.GoodStatus_ _ body ->
            case JD.decodeString decoder body of
                Ok value_ ->
                    Ok value_

                Err err ->
                    Err <| BadBody <| JD.errorToString err


expectJson : (Result Error a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg (resolution decoder)


expectWhatever : (Result Error () -> msg) -> Http.Expect msg
expectWhatever toMsg =
    let
        resolve : (body -> Result String a) -> Http.Response body -> Result Error a
        resolve toResult response =
            case response of
                Http.BadUrl_ url_ ->
                    Err <| BadUrl url_

                Http.Timeout_ ->
                    Err Timeout

                Http.NetworkError_ ->
                    Err NetworkError

                Http.BadStatus_ metadata _ ->
                    Err <| BadStatus metadata.statusCode emptyErrors

                Http.GoodStatus_ _ body ->
                    Result.mapError BadBody (toResult body)
    in
    Http.expectStringResponse toMsg (resolve (always <| Ok ()))


type alias PKPart pk =
    ( String, pk -> Value )


type PrimaryKey pk
    = PrimaryKey (List (PKPart pk))


primaryKey : PKPart pk -> PrimaryKey pk
primaryKey a =
    PrimaryKey [ a ]


primaryKey2 : PKPart pk -> PKPart pk -> PrimaryKey pk
primaryKey2 a b =
    PrimaryKey [ a, b ]


primaryKey3 : PKPart pk -> PKPart pk -> PKPart pk -> PrimaryKey pk
primaryKey3 a b c =
    PrimaryKey [ a, b, c ]


endpoint : String -> Decoder r -> Endpoint r
endpoint u decoder =
    Endpoint
        { url = BaseURL u
        , decoder = decoder
        , defaultSelect = Nothing
        , defaultOrder = Nothing
        }


customEndpoint :
    String
    -> Decoder r
    ->
        { defaultSelect : Maybe (List Selectable)
        , defaultOrder : Maybe (List ColumnOrder)
        }
    -> Endpoint r
customEndpoint u decoder { defaultSelect, defaultOrder } =
    Endpoint
        { url = BaseURL u
        , decoder = decoder
        , defaultSelect = defaultSelect
        , defaultOrder = defaultOrder
        }


type alias PostgrestErrorJSON =
    { message : Maybe String
    , details : Maybe String
    , hint : Maybe String
    , code : Maybe String
    }


decodePostgrestError : Decoder PostgrestErrorJSON
decodePostgrestError =
    map4 PostgrestErrorJSON
        (maybe (field "message" JD.string))
        (maybe (field "details" JD.string))
        (maybe (field "hint" JD.string))
        (maybe (field "code" JD.string))


emptyErrors : PostgrestErrorJSON
emptyErrors =
    PostgrestErrorJSON
        Nothing
        Nothing
        Nothing
        Nothing


type Error
    = Timeout
    | BadUrl String
    | NetworkError
    | BadStatus Int PostgrestErrorJSON
    | BadBody String


toHttpError : Error -> Http.Error
toHttpError e =
    case e of
        Timeout ->
            Http.Timeout

        BadUrl s ->
            Http.BadUrl s

        NetworkError ->
            Http.NetworkError

        BadStatus i _ ->
            Http.BadStatus i

        BadBody s ->
            Http.BadBody s


badStatusBodyToPostgrestError : Int -> String -> Error
badStatusBodyToPostgrestError statusCode body =
    case JD.decodeString decodePostgrestError body of
        Ok errors ->
            BadStatus statusCode errors

        Err _ ->
            BadStatus statusCode emptyErrors


jwtString : JWT -> String
jwtString =
    JWT.jwtString


jwt : String -> JWT
jwt =
    JWT.jwt


type alias JWT =
    JWT.JWT


type alias Request r =
    Request.Request r


type alias Endpoint r =
    Endpoint.Endpoint r
