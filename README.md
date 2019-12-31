# alex-tan/postgrest-client

[![Build Status](https://travis-ci.org/alex-tan/postgrest-client.svg?branch=master)](https://travis-ci.org/alex-tan/postgrest-client)

This package allows you to both easily construct [Postgrest query strings](http://postgrest.org/en/v5.1/api.html#horizontal-filtering-rows) and also make postgrest requests using Elm.

This library allows you to construct and execute requests in a typesafe manner, with
little boilerplate. Here's what a full example might look like:

```elm
module Api.People exposing (delete, getMany, post)

import Json.Decode exposing (..)
import Json.Encode as JE
import Postgrest.Client as P

-- Optional, but recommended to have a type that
-- represents your primary key.
type PersonID
    = PersonID Int


-- And a way to unwrap it...
personID : PersonID -> Int
personID (PersonID id) =
    id


-- Define the record you would fetch back from the server.
type alias Person =
    { id : PersonID
    , name : String
    }


-- Define a submission record, without the primary key.
type alias PersonSubmission =
    { name : String
    }


-- Decoders are written using Json.Decode
decodeUnit : Decoder Person
decodeUnit =
    map2 Person
        (field "id" <| map PersonID int)
        (field "name" string)


-- Encoders are written using Json.Encode
encode : PersonSubmission -> JE.Value
encode person =
    JE.object
        [ ( "name", JE.string person.name )
        ]


-- Tell Postgrest.Client the column name of your primary key and
-- how to convert it into a parameter.
primaryKey : P.PrimaryKey PersonID
primaryKey =
    P.primaryKey ( "id", P.int << personID )


-- Tell Postgrest.Client the URL of the postgrest endpoint and how
-- to decode records from it.
endpoint : P.Endpoint Person
endpoint =
    P.endpoint "/people" decodeUnit


-- Fetch many records. If you want to specify parameters use `setParams`
getMany : P.Request (List Person)
getMany =
    P.getMany endpoint


-- Delete by primary key. This is a convenience function that reduces
-- the likelihood that you delete the wrong records by specifying incorrect
-- parameters.
delete : PersonID -> P.Request PersonID
delete =
    P.deleteByPrimaryKey endpoint primaryKey


-- Create a record.
post : PersonSubmission -> P.Request Person
post =
    P.postOne endpoint << encode
```

Here's how you could use it:

```elm
import Api.People as People
import Postgrest.Client as P

jwt : P.JWT
jwt =
    P.jwt "myjwt"

type Msg 
    = PersonCreated (Result P.Error Person)
    | PeopleLoaded (Result P.Error (List Person))
    | PersonDeleted (Result P.Error PersonID)

toCmd = 
    P.toCmd jwt

cmdExamples =
    [ People.post
        { name = "Yasujirō Ozu"
        }
        |> P.toCmd jwt PersonCreated
    , People.getMany
        [ P.order [ P.asc "name" ], P.limit 10 ]
        |> toCmd PeopleLoaded
    , Person.delete personID
        |> toCmd PersonDeleted
    ]
```

Most query operators are currently supported:

* [select](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#select)
* [eq](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#eq)
* [gt](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#gt)
* [gte](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#gte)
* [lt](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#lt)
* [lte](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#lte)
* [neq](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#neq)
* [like](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#like)
* [ilike](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#ilike)
* [in](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#inList)
* [is.null](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#null)
* [is.true](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#true)
* [is.false](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#false)
* [fts](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#fts)
* [plfts](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#plfts)
* [phfts](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#plfts)
* [not](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client#not)

[View Full Documentation](https://package.elm-lang.org/packages/alex-tan/postgrest-client/latest/Postgrest-Client)


# URL Query Construction

## Using `select`


If you're not selecting any nested resources in your request, you can use `attributes`:

```elm
-- "select=id,name"
P.toQueryString
    [ P.select <| P.attributes [ "id", "name" ]
    ]
```

If you want to select attributes and resources, you can use the `attribute` and `resource` functions:

```elm
-- select=id,name,grades(percentage)
P.toQueryString
  [ P.select
      [ P.attribute "id"
      , P.attribute "name"
      , P.resource "grades"
          [ P.attribute "percentage"
          ]
      ]
  ]
```

The library also provides a nice abstraction that allows you to both specify nested resources in a select clause, as well as use other postgrest parameters on those nested resources such as `order`, `limit`, and all of the usual conditional parameters such as `eq`:


```elm
-- select=id,name,grades(percentage)&grades.order=percentage.desc&grades.limit=10
P.toQueryString
  [ P.select
      [ P.attribute "id"
      , P.attribute "name"
      , P.resourceWithParams "grades"
          [ P.order [ P.desc "percentage" ], P.limit 10 ]
          [ P.attribute "percentage"
          ]
      ]
  ]
```

## Conditions

The library currently supports the most commonly used query parameters. Here's a sampling of how they can be used in combination with one another:

```elm
-- student_id=eq.100&grade=gte.90&or=(self_evaluation.gte.90,self_evaluation.is.null)
P.toQueryString
  [ P.param "student_id" <| P.eq <| P.int 100
  , P.param "grade" <| P.gte <| P.int 90
  , P.or
      [ P.param "self_evaluation" <| P.gte <| P.int 90
      , P.param "self_evaluation" P.null
      ]
  ]
```

The `in` operator can be used with `inList`. The second parameter is a list of whatever values you're using in your app and the first argument is the function that will transform the items in that list into the library's `Value` type such as `string` or `int`.

```elm
-- name=in.("Chico","Harpo","Groucho")
P.toQueryString
  [ P.param "name" <| P.inList P.string [ "Chico", "Harpo", "Groucho" ]
  ]
```

## Order

You can order results by multiple columns as well as using `nullsfirst` or `nullslast`.

```elm
-- order=age.asc.nullsfirst,created_at.desc
P.toQueryString
  [ P.order
      [ P.asc "age" |> P.nullsfirst
      , P.desc "created_at"
      ]
  ]
```

## Combining Params

Maybe you have default parameters that you want to reuse across multiple functions. You can combine them using `combineParams`:

```elm
defaultParams : P.Params
defaultParams =
    [ P.select <| P.attributes [ "id", "name" ]
    , P.limit 10
    ]


constructParams : P.Params -> P.Params
constructParams =
    P.combineParams defaultParams


-- limit=100&select=id,name
constructParams [ P.limit 100 ]
```

Note that the merging of the two sets is not recursive. The two are merged by the final query parameter name such as `order` or `children.order`, etc... and the second set's value is always preferred.