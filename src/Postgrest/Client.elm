module Postgrest.Client exposing
    ( Endpoint
    , Request
    , endpoint
    , customEndpoint
    , getMany
    , getOne
    , postOne
    , getByPrimaryKey
    , patchByPrimaryKey
    , deleteByPrimaryKey
    , setCustomHeaders
    , setParams
    , setTimeout
    , get
    , post
    , unsafePatch
    , unsafeDelete
    , JWT, jwt, jwtString
    , toCmd, toTask
    , PrimaryKey
    , primaryKey
    , primaryKey2
    , primaryKey3
    , Error(..), PostgrestErrorJSON, toHttpError
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
    , contains
    , containedIn
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
    )

{-|


# postgrest-client

This library allows you to construct and execute postgrest requests with additional type safety.
Here's what `Api.People` might look like:

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
    -- to decode an individual record from it. Postgrest will combine
    -- the decoder with a list decoder automatically when necessary.
    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodeUnit

    -- Fetch many records. If you want to specify parameters use `setParams`
    getMany : P.Request (List Person)
    getMany =
        P.getMany endpoint

    -- Delete by primary key. This is a convenience function that reduces
    -- the likelihood that you delete more than one record by specifying incorrect
    -- parameters.
    delete : PersonID -> P.Request PersonID
    delete =
        P.deleteByPrimaryKey endpoint primaryKey

    -- Create a record.
    post : PersonSubmission -> P.Request Person
    post =
        P.postOne endpoint << encode

Here's how you could use it:

    import Api.People as People
    import Postgrest.Client as P

    jwt : P.JWT
    jwt =
        P.jwt "abcdefghijklmnopqrstuvwxyz1234"

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


# Request Construction and Modification

@docs Endpoint
@docs Request
@docs endpoint
@docs customEndpoint


# Endpoint a

@docs getMany
@docs getOne
@docs postOne
@docs getByPrimaryKey
@docs patchByPrimaryKey
@docs deleteByPrimaryKey


# Request Options

@docs setCustomHeaders
@docs setParams
@docs setTimeout


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

@docs Error, PostgrestErrorJSON, toHttpError


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


## Converting/Combining Parameters

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
@docs contains
@docs containedIn


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

import Http exposing (Resolver, task)
import Json.Decode as JD exposing (Decoder, decodeString, field, index, list, map, map4, maybe)
import Json.Encode as JE
import Postgrest.Internal.Endpoint as Endpoint exposing (Endpoint(..))
import Postgrest.Internal.JWT as JWT exposing (JWT)
import Postgrest.Internal.Params as Param exposing (ColumnOrder(..), Language, NullOption(..), Operator(..), Param(..), Selectable(..), Value(..))
import Postgrest.Internal.Requests as Request
    exposing
        ( Request(..)
        , RequestType(..)
        , defaultRequest
        , fullURL
        , mapRequest
        , requestTypeToBody
        , requestTypeToHTTPMethod
        , requestTypeToHeaders
        , setCustomHeaders
        , setMandatoryParams
        )
import Postgrest.Internal.URL exposing (BaseURL(..))
import Task exposing (Task)


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


{-| Limit the number of records that can be returned.

    limit 10

-}
limit : Int -> Param
limit =
    Limit


{-| Specify the offset in the query.

    offset 10

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

    P.order [ P.asc "name" ]

-}
asc : String -> ColumnOrder
asc s =
    Asc s Nothing


{-| Used in combination with `order` to sort results descending.

    P.order [ P.desc "name" ]

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


{-| Query, specifying that a value should be null.

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


{-| Use the `cs` operator.

    param "tag" <| contains <| List.map string [ "Chico", "Harpo", "Groucho" ]

    -- tag=cs.(\"Chico\",\"Harpo\",\"Groucho\")"

-}
contains : List Value -> Operator
contains l =
    Cs l


{-| Use the `cd` operator.

    param "tag" <| containedIn <| List.map string [ "Chico", "Harpo", "Groucho" ]

    -- tag=cd.(\"Chico\",\"Harpo\",\"Groucho\")"

-}
containedIn : List Value -> Operator
containedIn l =
    Cd l


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


{-| Used to set the parameters of your request.

    getPeople : P.Request (List Person)
    getPeople =
        P.getMany endpoint
            |> P.setParams
                [ P.order [ P.asc "first_name" ]
                , P.limit 20
                ]

-}
setParams : Params -> Request a -> Request a
setParams p =
    mapRequest (\req -> { req | overrideParams = p })


{-| Set custom headers for the request.

    getThings : String -> (Result P.Error (List Thing) -> msg) -> Cmd msg
    getThings jwt toMsg =
        let
            customHeaders =
                -- Some custom header we want to pass so that we can pull it from the request in PostgREST.
                -- For example a tenant identifier in a multi-tenant system. You could just encode this into the JWT,
                -- however you might run into a case where you can't provide a JWT, like for anonymous third party use
                -- of your API.
                [ Http.header "X-Tenant-ID" "12345" ]

            request =
                P.getMany someThingEndpoint
                    |> P.setCustomHeaders customHeaders
        in
        P.toCmd (Just (P.jwt jwt)) toMsg request

-}
setCustomHeaders : List Http.Header -> Request a -> Request a
setCustomHeaders =
    Request.setCustomHeaders


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
    List Param


{-| An individual postgrest parameter.
-}
type alias Param =
    Param.Param


{-| Used to GET multiple records from the provided endpoint.
Converts your endpoint decoder into `(list decoder)` to decode multiple records.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    getAll : P.Request (List Person)
    getAll =
        P.getMany endpoint
            |> P.setParams [ P.limit 20 ]

-}
getMany : Endpoint a -> Request (List a)
getMany e =
    defaultRequest e <| Get <| JD.list <| Endpoint.decoder e


{-| Used to GET a single record. Converts your endpoint decoder into `(index 0 decoder)` to extract
it from postgrest's JSON array response and sets `limit=1` in the parameters. If you're requesting by
primary key see `getOneByPrimaryKey`.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    getOnePersonByName : String -> P.Request Person
    getOnePersonByName name =
        P.getOne endpoint
            |> P.setParams [ P.param "name" <| P.eq name ]

-}
getOne : Endpoint a -> Request a
getOne e =
    (defaultRequest e <| Get <| JD.index 0 <| Endpoint.decoder e)
        |> setParams [ limit 1 ]


{-| The most basic way to make a get request.
-}
get :
    String
    ->
        { params : Params
        , decoder : Decoder a
        }
    -> Request a
get baseURL { params, decoder } =
    Request
        { options = Get decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        , customHeaders = []
        }


{-| The most basic way to make a post request.
-}
post :
    String
    ->
        { params : Params
        , decoder : Decoder a
        , body : JE.Value
        }
    -> Request a
post baseURL { params, decoder, body } =
    Request
        { options = Post body decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        , customHeaders = []
        }


{-| Titled unsafe because if you provide incorrect or no parameters it will make a PATCH request
to all resources the requesting user has access to at that endpoint. Use with caution.
See [Block Full-Table Operations](http://postgrest.org/en/v5.2/admin.html#block-fulltable).
-}
unsafePatch :
    String
    ->
        { body : JE.Value
        , decoder : Decoder a
        , params : Params
        }
    -> Request a
unsafePatch baseURL { body, decoder, params } =
    Request
        { options = Patch body decoder
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL baseURL
        , customHeaders = []
        }


type alias UnsafeDeleteOptions a =
    { params : Params
    , returning : a
    }


{-| Titled unsafe because if you provide incorrect or no parameters it will make a DELETE request
to all resources the requesting user has access to at that endpoint. Use with caution.
See [Block Full-Table Operations](http://postgrest.org/en/v5.2/admin.html#block-fulltable).
-}
unsafeDelete : String -> UnsafeDeleteOptions a -> Request a
unsafeDelete url { returning, params } =
    Request
        { options = Delete returning
        , timeout = Nothing
        , defaultParams = []
        , overrideParams = params
        , mandatoryParams = []
        , baseURL = BaseURL url
        , customHeaders = []
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


{-| Used to GET a single record by primary key. This is the recommended way to do a singular GET request
assuming your table has a primary key.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    primaryKey : P.PrimaryKey Int
    primaryKey =
        P.primaryKey ( "id", P.int )

    getByPrimaryKey : Int -> P.Request Person
    getByPrimaryKey =
        P.getByPrimaryKey endpoint primaryKey

-}
getByPrimaryKey : Endpoint a -> PrimaryKey p -> p -> Request a
getByPrimaryKey e primaryKeyToParams_ primaryKey_ =
    defaultRequest e (Get <| index 0 <| Endpoint.decoder e)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams_ primaryKey_)


{-| Used to PATCH a single record by primary key. This is the recommended way to do a PATCH request
assuming your table has a primary key. The decoder will decode the record after it's been patched if the request is successful.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    primaryKey =
        P.primaryKey ( "id", P.int )

    updatePerson : PersonForm -> Int -> P.Request Person
    updatePerson submission id =
        P.patchByPrimaryKey endpoint primaryKey (encodeSubmission submission)

    -- Would create a request to patch to "/people?id=eq.3"
    updatePerson form 3

-}
patchByPrimaryKey : Endpoint a -> PrimaryKey p -> p -> JE.Value -> Request a
patchByPrimaryKey e primaryKeyToParams primaryKey_ body =
    defaultRequest e (Patch body <| index 0 <| Endpoint.decoder e)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams primaryKey_)


{-| Used to DELETE a single record by primary key. This is the recommended way to do a DELETE request
if your table has a primary key. The decoder will decode the record after it's been patched if the request is successful.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    primaryKey =
        P.primaryKey ( "id", P.int )

    delete : Int -> P.Request Int
    delete =
        P.deleteByPrimaryKey endpoint primaryKey

    -- Would create a request to DELETE to "/people?id=eq.3"
    -- and the success value would be the ID passed in.
    -- So your Msg would look like:
    -- | DeleteSuccess (Result P.Error Int)
    delete 3

-}
deleteByPrimaryKey : Endpoint a -> PrimaryKey p -> p -> Request p
deleteByPrimaryKey e primaryKeyToParams primaryKey_ =
    defaultRequest e (Delete primaryKey_)
        |> setMandatoryParams (primaryKeyEqClause primaryKeyToParams primaryKey_)


{-| Used to create a single record at the endpoint you provide and an encoded JSON value.

    endpoint : P.Endpoint Person
    endpoint =
        P.endpoint "/people" decodePerson

    encodePerson : Person -> JE.Value
    encodePerson p =
        object
            [ ( "first_name", JE.string p.firstName )
            , ( "last_name", JE.string p.lastName )
            ]

    post : PersonForm -> P.Request Person
    post submission =
        P.postOne endpoint (encodePerson submission)

-}
postOne : Endpoint a -> JE.Value -> Request a
postOne e body =
    defaultRequest e <| Post body <| index 0 <| Endpoint.decoder e


{-| Takes a JWT, Msg and a Request and turns it into a Cmd.
-}
toCmd : Maybe JWT -> (Result Error a -> msg) -> Request a -> Cmd msg
toCmd jwt_ toMsg (Request options) =
    Http.request
        { method = requestTypeToHTTPMethod options.options
        , headers = requestTypeToHeaders jwt_ options.options options.customHeaders
        , url = fullURL options
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


{-| Takes a JWT and a Request and turns it into a Task.
-}
toTask : Maybe JWT -> Request a -> Task Error a
toTask jwt_ (Request o) =
    let
        { options } =
            o
    in
    task
        { body = requestTypeToBody options
        , timeout = o.timeout
        , url = fullURL o
        , method = requestTypeToHTTPMethod options
        , headers = requestTypeToHeaders jwt_ options o.customHeaders
        , resolver =
            case options of
                Delete returning ->
                    Http.stringResolver <| always <| Ok returning

                Get decoder ->
                    jsonResolver decoder

                Post _ decoder ->
                    jsonResolver decoder

                Patch _ decoder ->
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
                    Err <| BadStatus metadata.statusCode "" emptyErrors

                Http.GoodStatus_ _ body ->
                    Result.mapError BadBody <| toResult body
    in
    Http.expectStringResponse toMsg <| resolve <| always <| Ok ()


{-| Can be used together with endpoint to make request construction easier. See
[primaryKey](#primaryKey) and [endpoint](#endpoint).
-}
type PrimaryKey pk
    = PrimaryKey (List ( String, pk -> Value ))


{-| Used to construct a primary key made up of one column.
Takes a tuple of the column name of your primary key and a function
to convert your elm representation of that primary key into a postgrest parameter.

    primaryKey : P.PrimaryKey Int
    primaryKey =
        primaryKey ( "id", P.int )

is the simplest example. If you have custom type to represent your primary key you
could do this:

    type ID
        = ID Int

    idToInt : ID -> Int
    idToInt (ID id) =
        id

    primaryKey : P.PrimaryKey ID
    primaryKey =
        P.primaryKey ( "id", P.int << idToInt )

-}
primaryKey : ( String, pk -> Value ) -> PrimaryKey pk
primaryKey a =
    PrimaryKey [ a ]


{-| Used to construct a primary key made up of two columns.
Takes two tuples, each with a column name and a function
to convert your elm representation of that primary key into a postgrest parameter.

    primaryKey2 ( "id", P.int )

is the simplest example. If you have custom type to represent your primary key you
could do this:

    type alias ParentID =
        Int

    type alias Category =
        String

    type alias MyPrimaryKey =
        ( ParentID, Category )

    primaryKey : P.PrimaryKey MyPrimaryKey
    primaryKey =
        P.primaryKey2
            ( "parent_id", P.int << Tuple.first )
            ( "category", P.string << Tuple.second )

-}
primaryKey2 : ( String, pk -> Value ) -> ( String, pk -> Value ) -> PrimaryKey pk
primaryKey2 a b =
    PrimaryKey [ a, b ]


{-| Used to construct primary keys that are made up of three columns. See [primaryKey2](#primaryKey2) for
a similar example of how this could be used.
-}
primaryKey3 : ( String, pk -> Value ) -> ( String, pk -> Value ) -> ( String, pk -> Value ) -> PrimaryKey pk
primaryKey3 a b c =
    PrimaryKey [ a, b, c ]


{-| The simplest way to define an endpoint. You provide it the URL and a decoder.
It can then be used to quickly construct POST, GET, PATCH, and DELETE requests.
The decoder provided should just be a decoder of the record itself, not a decoder of
an object inside an array.

    decodePerson : Decoder Person
    decodePerson =
        map2 Person
            (field "first_name" string)
            (field "last_name" string)

    peopleEndpoint : P.Endpoint Person
    peopleEndpoint =
        P.endpoint "/rest/people" decodePerson

-}
endpoint : String -> Decoder a -> Endpoint a
endpoint a decoder =
    Endpoint
        { url = BaseURL a
        , decoder = decoder
        , defaultSelect = Nothing
        , defaultOrder = Nothing
        }


{-| Define an endpoint with extra options. To quickly construct POST, GET, PATCH, and DELETE requests.
`defaultOrder` and `defaultSelect` can be overriden by using `setParams` once a request is constructed.

    peopleEndpoint : P.Endpoint Person
    peopleEndpoint =
        P.endpoint "/rest/people"
            decodePerson
            { defaultSelect = Just [ P.attribute "id", P.attribute "name" ]
            , defaultOrder = Just [ P.asc "name" ]
            }

-}
customEndpoint :
    String
    -> Decoder a
    ->
        { defaultSelect : Maybe (List Selectable)
        , defaultOrder : Maybe (List ColumnOrder)
        }
    -> Endpoint a
customEndpoint u decoder { defaultSelect, defaultOrder } =
    Endpoint
        { url = BaseURL u
        , decoder = decoder
        , defaultSelect = defaultSelect
        , defaultOrder = defaultOrder
        }


{-| Contains any details postgrest might have given us about a failed request.
-}
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


{-| `Error` Looks a lot like `Http.Error` except `BadStatus` includes a second argument,
`PostgrestErrorJSON` with any details that postgrest might have given us about a failed request.
-}
type Error
    = Timeout
    | BadUrl String
    | NetworkError
    | BadStatus Int String PostgrestErrorJSON
    | BadBody String


{-| Converts the custom HTTP error used by this package into an elm/http Error.
This can be useful if you're using `Task.map2`, `Task.map3`, etc... and each of the
tasks need to have the same error type.
-}
toHttpError : Error -> Http.Error
toHttpError e =
    case e of
        Timeout ->
            Http.Timeout

        BadUrl s ->
            Http.BadUrl s

        NetworkError ->
            Http.NetworkError

        BadStatus i _ _ ->
            Http.BadStatus i

        BadBody s ->
            Http.BadBody s


badStatusBodyToPostgrestError : Int -> String -> Error
badStatusBodyToPostgrestError statusCode body =
    BadStatus statusCode body <| bodyToPostgrestErrors body


bodyToPostgrestErrors : String -> PostgrestErrorJSON
bodyToPostgrestErrors body =
    case JD.decodeString decodePostgrestError body of
        Ok errors ->
            errors

        Err _ ->
            emptyErrors


{-| If you've already created a JWT with `jwt` you can extract the original string with
this function.

    myJWT = P.jwt "abcdef"

    jwtString myJWT -- "abcdef"

-}
jwtString : JWT -> String
jwtString =
    JWT.jwtString


{-| Pass the jwt string into this function to make it a JWT. This is used with `toCmd` and `toTask`
to make requests.

    myJWT =
        P.jwt "abcdef"

-}
jwt : String -> JWT
jwt =
    JWT.jwt


{-| The type used to store the JWT string.
-}
type alias JWT =
    JWT.JWT


{-| Request can be used with toCmd and toTask to make a request.
-}
type alias Request r =
    Request.Request r


{-| Sets the timeout of your request. The behaviour is the same
of that in the elm/http package.
-}
setTimeout : Float -> Request a -> Request a
setTimeout =
    Request.setTimeout


{-| Think of an Endpoint as a combination between a base url like `/schools` and
an elm/json `Decoder`. The endpoint can be passed to other functions in this library,
sometimes along with PrimaryKey to make constructing certain types of requests easier.
-}
type alias Endpoint a =
    Endpoint.Endpoint a
