module PostgrestTests exposing (suite)

import Expect exposing (Expectation)
import Postgrest.Client as P exposing (..)
import Test exposing (..)


matching =
    [ ( "age=lt.13", [ param "age" <| lt <| int 13 ] )
    , ( "age=gte.18&student=is.true"
      , [ param "age" <| gte <| int 18
        , param "student" <| true
        ]
      )
    , ( "or=(age.gte.14,age.lte.18)"
      , [ or
            [ param "age" <| gte <| int 14
            , param "age" <| lte <| int 18
            ]
        ]
      )
    , ( "and=(grade.gte.90,student.is.true,or(age.gte.14,age.is.null))"
      , [ and
            [ param "grade" <| gte <| int 90
            , param "student" <| true
            , or
                [ param "age" <| gte <| int 14
                , param "age" <| null
                ]
            ]
        ]
      )
    , ( "my_tsv=fts(french).amusant"
      , [ param "my_tsv" <| fts (Just "french") "amusant"
        ]
      )
    , ( "my_tsv=plfts.The%20Fat%20Cats"
      , [ param "my_tsv" <| plfts Nothing "The Fat Cats"
        ]
      )
    , ( "my_tsv=not.phfts(english).The%20Fat%20Cats"
      , [ param "my_tsv" <| P.not <| phfts (Just "english") "The Fat Cats"
        ]
      )
    , ( "select=first_name,age"
      , [ select <| attributes [ "first_name", "age" ] ]
      )
    , ( "select=fullName:full_name,birthDate:birth_date"
      , [ select <|
            [ attribute "fullName:full_name"
            , attribute "birthDate:birth_date"
            ]
        ]
      )
    , ( "order=age.desc,height.asc"
      , [ order
            [ desc "age"
            , asc "height"
            ]
        ]
      )
    , ( "order=age.asc.nullsfirst"
      , [ order
            [ asc "age" |> nullsfirst
            ]
        ]
      )
    , ( "order=age.desc.nullslast"
      , [ order
            [ desc "age" |> nullslast
            ]
        ]
      )
    , ( "limit=15&offset=30"
      , [ limit 15
        , offset 30
        ]
      )
    , ( "select=title,directors(id,last_name)"
      , [ select
            [ attribute "title"
            , resource "directors"
                [ attribute "id"
                , attribute "last_name"
                ]
            ]
        ]
      )
    , ( "select=*,roles(*)&roles.character=in.(\"Chico\",\"Harpo\",\"Groucho\")"
      , [ select
            [ attribute "*"
            , resource "roles" allAttributes
            ]
        , param "roles.character" <| inList string [ "Chico", "Harpo", "Groucho" ]
        ]
      )
    , ( "select=*,roles(*)&roles.or=(character.eq.Gummo,character.eq.Zeppo)"
      , [ select
            [ attribute "*"
            , resource "roles" [ attribute "*" ]
            ]
        , nestedParam [ "roles" ] <|
            or
                [ param "character" <| eq <| string "Gummo"
                , param "character" <| eq <| string "Zeppo"
                ]
        ]
      )
    , ( "select=*,actors(*)&actors.limit=10&actors.offset=2"
      , [ select
            [ attribute "*"
            , resource "actors" allAttributes
            ]
        , nestedParam [ "actors" ] <| limit 10
        , nestedParam [ "actors" ] <| offset 2
        ]
      )
    , ( "a=like.a*c", [ param "a" <| like "a*c" ] )
    , ( "a=ilike.a*c", [ param "a" <| ilike "a*c" ] )
    , ( "foo=is.false", [ P.param "foo" P.false ] )
    , ( "foo=is.true", [ P.param "foo" P.true ] )
    , ( "foo=is.null", [ P.param "foo" P.null ] )
    , ( "tag=cs.{foo,bar}", [ P.param "tag" <| P.contains <| List.map P.string [ "foo", "bar" ] ] )
    , ( "tag=cd.{foo,bar}", [ P.param "tag" <| P.containedIn <| List.map P.string [ "foo", "bar" ] ] )
    ]


suite : Test
suite =
    describe "operators"
        [ describe "documentation examples"
            (matching
                |> List.map
                    (\( v, s ) ->
                        test v <|
                            \_ ->
                                Expect.equal v (toQueryString s)
                    )
            )
        , describe "nested param options"
            [ test "nested params options" <|
                \_ ->
                    let
                        actual =
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

                        expected =
                            "select=sites(streams(*))&sites.streams.order=name.asc"
                    in
                    Expect.equal actual expected
            ]
        , describe "combine params"
            [ test "last ones take precedent" <|
                \_ ->
                    let
                        sortParams =
                            normalizeParams >> List.sortBy Tuple.first

                        expected =
                            [ P.param "a" <| eqString "1"
                            , P.param "c" <| eqString "3"
                            , P.param "b" <| eqString "5"
                            ]
                                |> sortParams

                        eqString =
                            P.eq << P.string

                        set =
                            [ [ P.param "a" <| eqString "1", P.param "b" <| eqString "2" ]
                            , [ P.param "c" <| eqString "3", P.param "b" <| eqString "4" ]
                            , [ P.param "b" <| eqString "5" ]
                            ]

                        actual =
                            P.concatParams set
                                |> sortParams
                    in
                    Expect.equal expected actual
            ]
        ]
