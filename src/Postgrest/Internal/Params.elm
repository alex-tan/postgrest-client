module Postgrest.Internal.Params exposing
    ( ColumnOrder(..)
    , Language
    , NullOption(..)
    , Operator(..)
    , Param(..)
    , Params
    , Selectable(..)
    , Value(..)
    , combineParams
    , concatParams
    , nestedParam
    , normalizeParams
    , order
    , select
    , toQueryString
    )

import Dict exposing (Dict)
import Url


type alias Params =
    List Param


type Param
    = Param String Operator
    | NestedParam String Param
    | Select (List Selectable)
    | Limit Int
    | Offset Int
    | Order (List ColumnOrder)
    | Or (List Param)
    | And (List Param)


type ColumnOrder
    = Asc String (Maybe NullOption)
    | Desc String (Maybe NullOption)


type NullOption
    = NullsFirst
    | NullsLast


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


type Selectable
    = Attribute String
    | Resource String (List Param) (List Selectable)


type Value
    = String String
    | Int Int
    | List (List Value)


type alias Language =
    String


order : List ColumnOrder -> Param
order =
    Order


select : List Selectable -> Param
select =
    Select


concatParams : List Params -> Params
concatParams =
    List.foldl
        (\a acc ->
            combineParams acc a
        )
        []


combineParams : Params -> Params -> Params
combineParams defaults override =
    Dict.union
        (dictifyParams override)
        (dictifyParams defaults)
        |> Dict.values


dictifyParams : Params -> Dict String Param
dictifyParams =
    List.map (\p -> ( postgrestParamKey p, p )) >> Dict.fromList


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
            "like." ++ (stringifyQuoted <| String s)

        Ilike s ->
            "ilike." ++ (stringifyQuoted <| String s)

        Plfts lang val ->
            fullTextSearch "plfts" lang val

        Phfts lang val ->
            fullTextSearch "phfts" lang val


catMaybes : List (Maybe a) -> List a
catMaybes =
    List.filterMap identity


fullTextSearch : String -> Maybe String -> String -> String
fullTextSearch operator lang val =
    operator
        ++ (lang
                |> Maybe.map surroundInParens
                |> Maybe.withDefault ""
           )
        ++ "."
        ++ stringifyValue Basics.False (String val)


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


nestedParam : List String -> Param -> Param
nestedParam path =
    NestedParam (String.join "." path)


toQueryString : Params -> String
toQueryString =
    normalizeParams
        >> List.map paramToString
        >> String.join "&"
