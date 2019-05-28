module Postgrest exposing
    ( Endpoint
    , Request
    , endpoint
    , getByPrimaryKey
    , getMany
    , postOne
    , patchByPrimaryKey
    , unsafePatch
    , deleteByPrimaryKey
    , setParams
    , JWT, jwt, toCmd, toTask
    , table, prefixedTable, customURL
    , Error(..), toHttpError
    , Param, Params, Selectable, ColumnOrder, Value
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
    , primaryKey, primaryKey2, primaryKey3
    )

{-|


# Request Construction and Modification

@docs Endpoint
@docs Request
@docs endpoint
@docs getByPrimaryKey
@docs getMany
@docs postOne
@docs patchByPrimaryKey
@docs unsafePatch
@docs deleteByPrimaryKey
@docs setParams


# Request Authentication and Execution

@docs JWT, jwt, toCmd, toTask


# URL Construction

@docs table, prefixedTable, customURL


# Errors

@docs Error, toHttpError


# Types

@docs Param, Params, Selectable, ColumnOrder, Value
@docs Operator


# Select

@docs select
@docs allAttributes
@docs attribute
@docs attributes
@docs resource
@docs resourceWithParams


# Converting/combining into something usable

@docs combineParams
@docs concatParams
@docs normalizeParams
@docs toQueryString


# Param

@docs param
@docs or
@docs and
@docs nestedParam


# Operators

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


# Values

@docs string
@docs int
@docs list


# Order

@docs order
@docs asc
@docs desc
@docs nullsfirst
@docs nullslast


# Full-Text Search

@docs plfts
@docs phfts
@docs fts

-}

import Dict exposing (Dict)
import Http exposing (Resolver, header, task)
import Json.Decode as JD exposing (Decoder, decodeString, field, index, list, map, map4, maybe)
import Json.Encode as JE
import Task exposing (Task)
import Url


{-| A collection of parameters that make up a postgrest request.
-}
type alias Params =
    List Param


{-| An individual postgrest parameter.
-}
type Param
    = Param String Operator
    | NestedParam String Param
    | Select (List Selectable)
    | Limit Int
    | Offset Int
    | Order (List ColumnOrder)
    | Or (List Param)
    | And (List Param)


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
nestedParam path =
    NestedParam (String.join "." path)


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
    Select


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


{-| A constructor for the limit parameter.

    order (asc "name")

    order (desc "name")

-}
order : List ColumnOrder -> Param
order =
    Order


{-| Type that can be represented in the queries: strings, ints and lists.
-}
type Value
    = String String
    | Int Int
    | List (List Value)


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


{-| A type to specify whether you want an order to be ascending or descending, and
optionally whether you want nulls to be first or last.
-}
type ColumnOrder
    = Asc String (Maybe NullOption)
    | Desc String (Maybe NullOption)


type NullOption
    = NullsFirst
    | NullsLast


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


{-| A type that represents the clause of a query. In `name=eq.John` the clause would be the part
after the equal sign.
-}
type Operator
    = Eq Value
    | GT Value
    | GTE Value
    | LT Value
    | LTE Value
    | Neq Value
    | Like String
    | Ilike String
    | In Value
    | Null
    | True
    | False
    | Fts (Maybe Language) String
    | Plfts (Maybe Language) String
    | Phfts (Maybe Language) String
      -- | Cs (List Value)
      -- | Cd (List Value)
      -- | Ov Range
      -- | Sl Range
      -- | Sr Range
      -- | Nxr Range
      -- | Nxl Range
      -- | Adj Range
    | Not Operator
    | Value Value


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


type alias Language =
    String


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
    LT


{-| Used to indicate you need a column to be greater than a certain value.
-}
gt : Value -> Operator
gt =
    GT


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
    True


{-| When you need a column value to be false

    -- foo=is.false
    [ P.param "foo" P.false ]
        |> toQueryString

-}
false : Operator
false =
    False


{-| A type representing which attributes and resources you want to select.
It also contains parameters that target nested resources.
-}
type Selectable
    = Attribute String
    | Resource String (List Param) (List Selectable)


{-| When you want to select a certain column.
-}
attribute : String -> Selectable
attribute =
    Attribute


{-| When you want to select a nested resource with no special parameters for the nested
resources. If you do want to specify parameters, see `resourceWithParams`.
-}
resource : String -> List Selectable -> Selectable
resource name selectable =
    Resource name [] selectable


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


postgrestParamKey : Param -> String
postgrestParamKey p =
    case p of
        Limit _ ->
            "limit"

        Offset _ ->
            "offset"

        Param k _ ->
            k

        Select _ ->
            "select"

        Order _ ->
            "order"

        Or _ ->
            "or"

        And _ ->
            "and"

        NestedParam r param_ ->
            r ++ "." ++ postgrestParamKey param_


postgrestParamValue : Param -> String
postgrestParamValue p =
    case p of
        Param _ clause ->
            stringifyClause clause

        Select attrs ->
            attrs
                |> List.map stringifySelect
                |> String.join ","

        Limit i ->
            String.fromInt i

        Offset i ->
            String.fromInt i

        Order os ->
            os
                |> List.map
                    (\o ->
                        case o of
                            Asc field nullOption ->
                                [ Just field
                                , Just "asc"
                                , stringifyNullOption nullOption
                                ]
                                    |> catMaybes
                                    |> String.join "."

                            Desc field nullOption ->
                                [ Just field
                                , Just "desc"
                                , stringifyNullOption nullOption
                                ]
                                    |> catMaybes
                                    |> String.join "."
                    )
                |> String.join ","

        And c ->
            wrapConditions c

        Or c ->
            wrapConditions c

        NestedParam _ nestedParam_ ->
            postgrestParamValue nestedParam_


stringifyNullOption : Maybe NullOption -> Maybe String
stringifyNullOption =
    Maybe.map
        (\n_ ->
            case n_ of
                NullsFirst ->
                    "nullsfirst"

                NullsLast ->
                    "nullslast"
        )


catMaybes : List (Maybe a) -> List a
catMaybes =
    List.filterMap identity


wrapConditions : Params -> String
wrapConditions =
    List.concatMap normalizeParam
        >> List.map paramToInnerString
        >> String.join ","
        >> surroundInParens


surroundInParens : String -> String
surroundInParens s =
    "(" ++ s ++ ")"


stringifyClause : Operator -> String
stringifyClause operator =
    case operator of
        Neq val ->
            "neq." ++ stringifyUnquoted val

        Eq val ->
            "eq." ++ stringifyUnquoted val

        In val ->
            "in.(" ++ stringifyQuoted val ++ ")"

        Value val ->
            stringifyUnquoted val

        True ->
            "is.true"

        False ->
            "is.false"

        Null ->
            "is.null"

        LT val ->
            "lt." ++ stringifyQuoted val

        LTE val ->
            "lte." ++ stringifyQuoted val

        GT val ->
            "gt." ++ stringifyQuoted val

        GTE val ->
            "gte." ++ stringifyQuoted val

        Not o ->
            "not." ++ stringifyClause o

        Fts lang val ->
            fullTextSearch "fts" lang val

        Like s ->
            "like." ++ (stringifyQuoted <| string s)

        Ilike s ->
            "ilike." ++ (stringifyQuoted <| string s)

        Plfts lang val ->
            fullTextSearch "plfts" lang val

        Phfts lang val ->
            fullTextSearch "phfts" lang val


fullTextSearch : String -> Maybe String -> String -> String
fullTextSearch operator lang val =
    operator
        ++ (lang
                |> Maybe.map surroundInParens
                |> Maybe.withDefault ""
           )
        ++ "."
        ++ stringifyValue Basics.False (string val)


stringifyUnquoted : Value -> String
stringifyUnquoted =
    stringifyValue Basics.False


stringifyQuoted : Value -> String
stringifyQuoted =
    stringifyValue Basics.True


stringifyValue : Bool -> Value -> String
stringifyValue quotes val =
    case val of
        String str ->
            if quotes then
                "\"" ++ Url.percentEncode str ++ "\""

            else
                Url.percentEncode str

        Int i ->
            String.fromInt i

        List l ->
            l
                |> List.map (stringifyValue quotes)
                |> String.join ","


stringifySelect : Selectable -> String
stringifySelect postgrestSelect =
    case postgrestSelect of
        Attribute attr ->
            attr

        Resource resourceName _ attrs ->
            case attrs of
                [] ->
                    resourceName

                _ ->
                    resourceName
                        ++ "("
                        ++ (attrs
                                |> List.map stringifySelect
                                |> String.join ","
                           )
                        ++ ")"


dictifyParams : Params -> Dict String Param
dictifyParams =
    List.map (\p -> ( postgrestParamKey p, p )) >> Dict.fromList


{-| Takes Params and returns the parameters as a list of (Key, Value) strings.
-}
normalizeParams : Params -> List ( String, String )
normalizeParams =
    List.concatMap normalizeParam


normalizeParam : Param -> List ( String, String )
normalizeParam p =
    case p of
        Select selection ->
            ( postgrestParamKey p, postgrestParamValue p ) :: selectionParams selection

        _ ->
            [ ( postgrestParamKey p, postgrestParamValue p ) ]


selectionParams : List Selectable -> List ( String, String )
selectionParams =
    List.concatMap (selectionParam [])


selectionParam : List String -> Selectable -> List ( String, String )
selectionParam context s =
    case s of
        Attribute _ ->
            []

        Resource name options_ nested ->
            let
                newContext =
                    context ++ [ name ]
            in
            List.map
                (\item ->
                    let
                        p =
                            nestedParam newContext item
                    in
                    ( postgrestParamKey p, postgrestParamValue p )
                )
                options_
                ++ List.concatMap (selectionParam newContext) nested


{-| Takes a default set of params and a custom set of params and prefers the second set.
Useful when you're constructing reusable functions that make similar queries.
-}
combineParams : Params -> Params -> Params
combineParams defaults override =
    Dict.union
        (dictifyParams override)
        (dictifyParams defaults)
        |> Dict.values


{-| Takes a list of Params and combines them, preferring the last sets first.
-}
concatParams : List Params -> Params
concatParams =
    List.foldl
        (\a acc ->
            combineParams acc a
        )
        []


paramToString : ( String, String ) -> String
paramToString ( k, v ) =
    k ++ "=" ++ v


paramToInnerString : ( String, String ) -> String
paramToInnerString ( k, v ) =
    case k of
        "and" ->
            k ++ v

        "or" ->
            k ++ v

        _ ->
            k ++ "." ++ v


{-| Takes Params and returns a query string such as
`foo=eq.bar&baz=is.true`
-}
toQueryString : Params -> String
toQueryString =
    normalizeParams
        >> List.map paramToString
        >> String.join "&"


type JWT
    = JWT String


jwt : String -> JWT
jwt =
    JWT


type Request r
    = Request (RequestOptions r)
    | InvalidRequest


type alias RequestOptions r =
    { options : RequestType r
    , timeout : Maybe Float
    , defaultParams : Params
    , overrideParams : Params
    , mandatoryParams : Params
    , baseURL : String
    }


defaultRequest : Endpoint p r -> RequestType returning -> Request returning
defaultRequest e requestType =
    Request
        { options = requestType
        , timeout = Nothing
        , defaultParams = endpointToDefaultParams e
        , overrideParams = []
        , mandatoryParams = []
        , baseURL = endpointToBaseURL e
        }


setParams : Params -> Request r -> Request r
setParams p =
    mapRequest (\req -> { req | overrideParams = p })


setMandatoryParams : Params -> Request r -> Request r
setMandatoryParams p =
    mapRequest (\req -> { req | mandatoryParams = p })


mapRequest : (RequestOptions r -> RequestOptions r) -> Request r -> Request r
mapRequest f req =
    case req of
        Request options ->
            Request (f options)

        InvalidRequest ->
            InvalidRequest


url : RequestOptions r -> String
url { defaultParams, overrideParams, mandatoryParams, baseURL } =
    let
        params =
            concatParams [ defaultParams, overrideParams, mandatoryParams ]
    in
    baseURL ++ "?" ++ toQueryString params


type RequestType r
    = Post JE.Value (Decoder r)
    | Patch JE.Value (Decoder r)
    | Get (Decoder r)
    | Delete r


getMany : Endpoint p r -> Request (List r)
getMany e =
    defaultRequest e <| Get <| JD.list e.decoder


primaryKeyEqClause : PrimaryKeyConverter primaryKey -> primaryKey -> Params
primaryKeyEqClause converter pk =
    let
        pkPartToParam ( key, toParam ) =
            param key <| eq <| toParam pk

        targetCondition =
            case converter of
                PrimaryKeyConverter a ->
                    pkPartToParam a

                PrimaryKeyConverter2 a b ->
                    and
                        [ pkPartToParam a
                        , pkPartToParam b
                        ]

                PrimaryKeyConverter3 a b c ->
                    and
                        [ pkPartToParam a
                        , pkPartToParam b
                        , pkPartToParam c
                        ]
    in
    [ targetCondition
    , limit 1
    ]


getByPrimaryKey : Endpoint p r -> p -> Request r
getByPrimaryKey e primaryKey_ =
    case e.primaryKeyToParams of
        Just primaryKeyToParams_ ->
            defaultRequest e (Get <| index 0 e.decoder)
                |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams_ primaryKey_)

        Nothing ->
            InvalidRequest


patchByPrimaryKey : Endpoint pk record -> pk -> JE.Value -> Request record
patchByPrimaryKey e primaryKey_ body =
    case e.primaryKeyToParams of
        Just primaryKeyToParams_ ->
            defaultRequest e (Patch body <| index 0 e.decoder)
                |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams_ primaryKey_)

        Nothing ->
            InvalidRequest


deleteByPrimaryKey : Endpoint p r -> p -> Request p
deleteByPrimaryKey e primaryKey_ =
    case e.primaryKeyToParams of
        Just primaryKeyToParams_ ->
            defaultRequest e (Delete primaryKey_)
                |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams_ primaryKey_)

        Nothing ->
            InvalidRequest


postOne : Endpoint p r -> JE.Value -> Request r
postOne e body =
    defaultRequest e <| Post body <| index 0 e.decoder


unsafePatch : Endpoint p r -> JE.Value -> Request (List r)
unsafePatch e body =
    defaultRequest e <| Patch body <| JD.list e.decoder


toCmd : JWT -> (Result Error r -> msg) -> Request r -> Cmd msg
toCmd jwt_ toMsg request =
    case request of
        Request options ->
            let
                timeout_ =
                    options.timeout

                url_ =
                    url options
            in
            case options.options of
                Post body decoder ->
                    Http.request
                        { method = "POST"
                        , headers = [ jwtHeader jwt_, returnRepresentationHeader ]
                        , url = url_
                        , body = Http.jsonBody body
                        , expect = expectJson toMsg decoder
                        , timeout = timeout_
                        , tracker = Nothing
                        }

                Get decoder ->
                    Http.request
                        { method = "GET"
                        , headers = [ jwtHeader jwt_ ]
                        , url = url_
                        , body = Http.emptyBody
                        , expect = expectJson toMsg decoder
                        , timeout = timeout_
                        , tracker = Nothing
                        }

                Patch body decoder ->
                    Http.request
                        { method = "PATCH"
                        , headers = [ jwtHeader jwt_, returnRepresentationHeader ]
                        , url = url_
                        , body = Http.jsonBody body
                        , expect = expectJson toMsg decoder
                        , timeout = timeout_
                        , tracker = Nothing
                        }

                Delete returning ->
                    Http.request
                        { method = "DELETE"
                        , headers = [ jwtHeader jwt_ ]
                        , url = url_
                        , body = Http.emptyBody
                        , expect = expectWhatever (toMsg << Result.map (always returning))
                        , timeout = timeout_
                        , tracker = Nothing
                        }

        InvalidRequest ->
            Cmd.none


toTask : JWT -> Request r -> Task Error r
toTask jwt_ request =
    case request of
        Request options ->
            let
                timeout_ =
                    options.timeout

                url_ =
                    url options
            in
            case options.options of
                Post body decoder ->
                    task
                        { method = "POST"
                        , headers = [ jwtHeader jwt_, returnRepresentationHeader ]
                        , url = url_
                        , body = Http.jsonBody body
                        , resolver = jsonResolver decoder
                        , timeout = timeout_
                        }

                Get decoder ->
                    task
                        { method = "GET"
                        , headers = [ jwtHeader jwt_ ]
                        , url = url_
                        , body = Http.emptyBody
                        , resolver = jsonResolver decoder
                        , timeout = timeout_
                        }

                Patch body decoder ->
                    task
                        { method = "PATCH"
                        , headers = [ jwtHeader jwt_, returnRepresentationHeader ]
                        , url = url_
                        , body = Http.jsonBody body
                        , resolver = jsonResolver decoder
                        , timeout = timeout_
                        }

                Delete returning ->
                    task
                        { method = "DELETE"
                        , headers = [ jwtHeader jwt_ ]
                        , url = url_
                        , body = Http.emptyBody
                        , resolver = Http.stringResolver <| always <| Ok returning
                        , timeout = timeout_
                        }

        InvalidRequest ->
            Task.fail UnspecifiedPrimaryKeyToParams


returnRepresentationHeader : Http.Header
returnRepresentationHeader =
    header "Prefer" "return=representation"


jwtHeader : JWT -> Http.Header
jwtHeader (JWT jwt_) =
    Http.header "Authorization" <| "Bearer " ++ jwt_


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


type alias Endpoint primaryKey record =
    { url : URL
    , primaryKeyToParams : Maybe (PrimaryKeyConverter primaryKey)
    , decoder : Decoder record
    , defaultSelect : Maybe (List Selectable)
    , defaultOrder : Maybe (List ColumnOrder)
    , defaultLimit : Maybe Int
    }


type alias PKPart pk =
    ( String, pk -> Value )


type PrimaryKeyConverter pk
    = PrimaryKeyConverter (PKPart pk)
    | PrimaryKeyConverter2 (PKPart pk) (PKPart pk)
    | PrimaryKeyConverter3 (PKPart pk) (PKPart pk) (PKPart pk)


primaryKey : PKPart pk -> PrimaryKeyConverter pk
primaryKey a =
    PrimaryKeyConverter a


primaryKey2 : PKPart pk -> PKPart pk -> PrimaryKeyConverter pk
primaryKey2 a b =
    PrimaryKeyConverter2 a b


primaryKey3 : PKPart pk -> PKPart pk -> PKPart pk -> PrimaryKeyConverter pk
primaryKey3 a b c =
    PrimaryKeyConverter3 a b c


endpoint : Endpoint pk r -> Endpoint pk r
endpoint =
    identity


endpointToDefaultParams : Endpoint p r -> Params
endpointToDefaultParams { defaultSelect, defaultOrder, defaultLimit } =
    [ defaultSelect |> Maybe.map select
    , defaultOrder |> Maybe.map order
    , defaultLimit |> Maybe.map limit
    ]
        |> List.filterMap identity


type URL
    = Table String
    | PrefixedTable String String
    | URL String


table : String -> URL
table =
    Table


prefixedTable : String -> String -> URL
prefixedTable =
    PrefixedTable


customURL : String -> URL
customURL =
    URL


endpointToBaseURL : Endpoint primaryKey record -> String
endpointToBaseURL e =
    case e.url of
        Table tableName ->
            "/" ++ tableName

        PrefixedTable prefix tableName ->
            prefix ++ "/" ++ tableName

        URL u ->
            u


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
    | UnspecifiedPrimaryKeyToParams


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

        UnspecifiedPrimaryKeyToParams ->
            Http.BadUrl "unspecified_primary_key_to_params"


badStatusBodyToPostgrestError : Int -> String -> Error
badStatusBodyToPostgrestError statusCode body =
    case JD.decodeString decodePostgrestError body of
        Ok errors ->
            BadStatus statusCode errors

        Err _ ->
            BadStatus statusCode emptyErrors
