module OpenApi.Config exposing
    ( Config, EffectType(..), ResponseVersionCheck, effectTypeToPackage, Format, Input, Path(..), Server(..)
    , init, inputFrom, pathFromString
    , withAutoConvertSwagger, AutoConvertSwagger(..), withEffectTypes, withFormat, withFormats, withGenerateTodos, withInput, withSwaggerConversionCommand, withSwaggerConversionUrl, withNoElmFormat, withKeepGoing
    , withOutputModuleName, withOverrides, withResponseVersionCheck, withServer, withWriteMergedTo, withWarnOnMissingEnums
    , autoConvertSwagger, inputs, outputDirectory, swaggerConversionCommand, swaggerConversionUrl, noElmFormat, keepGoing
    , oasPath, overrides, responseVersionCheck, writeMergedTo
    , toGenerationConfig, Generate, pathToString
    , defaultFormats
    )

{-|


# Types

@docs Config, EffectType, ResponseVersionCheck, effectTypeToPackage, Format, Input, Path, Server


# Creation

@docs init, inputFrom, pathFromString
@docs withAutoConvertSwagger, AutoConvertSwagger, withEffectTypes, withFormat, withFormats, withGenerateTodos, withInput, withSwaggerConversionCommand, withSwaggerConversionUrl, withNoElmFormat, withKeepGoing
@docs withOutputModuleName, withOverrides, withResponseVersionCheck, withServer, withWriteMergedTo, withWarnOnMissingEnums


# Config properties

@docs autoConvertSwagger, inputs, outputDirectory, swaggerConversionCommand, swaggerConversionUrl, noElmFormat, keepGoing


# Input properties

@docs oasPath, overrides, responseVersionCheck, writeMergedTo


# Output

@docs toGenerationConfig, Generate, pathToString


# Internal

@docs defaultFormats

-}

import Common
import Dict
import Elm
import Elm.Annotation
import Elm.Case
import Elm.Op
import Gen.Base64
import Gen.Bytes
import Gen.Date
import Gen.Json.Decode
import Gen.Json.Encode
import Gen.Maybe
import Gen.Parser.Advanced
import Gen.Result
import Gen.Rfc3339
import Gen.Time
import Gen.Url
import Gen.Uuid
import Json.Encode
import OpenApi
import OpenApi.Info
import Url
import Utils


{-| Main configuration for the OpenAPI code generator.
-}
type Config
    = Config
        { inputs : List Input
        , outputDirectory : String
        , generateTodos : Bool
        , autoConvertSwagger : AutoConvertSwagger
        , swaggerConversionUrl : String
        , swaggerConversionCommand : Maybe { command : String, args : List String }
        , staticFormats : List Format
        , dynamicFormats : List { format : String, basicType : Common.BasicType } -> List Format
        , noElmFormat : Bool
        , keepGoing : Bool
        }


{-| Whether to automatically convert Swagger files to OpenAPI files.

This features uses an external service.

-}
type AutoConvertSwagger
    = AlwaysConvert
    | NeverConvert
    | AskBeforeConversion


{-| An input OpenAPI spec.
-}
type Input
    = Input
        { oasPath : Path
        , outputModuleName : Maybe (List String)
        , server : Server
        , overrides : List Path
        , writeMergedTo : Maybe String
        , responseVersionCheck : Maybe ResponseVersionCheck
        , effectTypes : List EffectType
        , warnOnMissingEnums : Bool
        }


{-| Supported effect types.
-}
type EffectType
    = ElmHttpCmd -- `Http.request` from elm/http
    | ElmHttpCmdRecord -- The input to `Http.request` from elm/http
    | ElmHttpCmdRisky -- `Http.riskyRequest` from elm/http
    | ElmHttpTask -- `Http.task` from elm/http
    | ElmHttpTaskRecord -- The input to `Http.task` from elm/http
    | ElmHttpTaskRisky -- `Http.riskyTask` from elm/http
    | DillonkearnsElmPagesTask -- `BackendTask.Http.request` from dillonkearns/elm-pages
    | DillonkearnsElmPagesTaskRecord -- The input to `BackendTask.Http.request` from dillonkearns/elm-pages
    | LamderaProgramTestCmd -- `Effect.Http.request` from lamdera/program-test
    | LamderaProgramTestCmdRecord -- The input to `Effect.Http.request` from lamdera/program-test
    | LamderaProgramTestCmdRisky -- `Effect.Http.riskyRequest` from lamdera/program-test
    | LamderaProgramTestTask -- `Effect.Http.task` from lamdera/program-test
    | LamderaProgramTestTaskRecord -- The input to `Effect.Http.task` from lamdera/program-test
    | LamderaProgramTestTaskRisky -- `Effect.Http.riskyTask` from lamdera/program-test


{-| Configuration for exposing a response version header to the generated SDK.
-}
type alias ResponseVersionCheck =
    { headerName : String
    }


{-| Gets the package that an `EffectType` is defined in.
-}
effectTypeToPackage : EffectType -> Common.Package
effectTypeToPackage effectType =
    case effectType of
        ElmHttpCmd ->
            Common.ElmHttp

        ElmHttpCmdRisky ->
            Common.ElmHttp

        ElmHttpCmdRecord ->
            Common.ElmHttp

        ElmHttpTask ->
            Common.ElmHttp

        ElmHttpTaskRisky ->
            Common.ElmHttp

        ElmHttpTaskRecord ->
            Common.ElmHttp

        DillonkearnsElmPagesTaskRecord ->
            Common.ElmHttp

        DillonkearnsElmPagesTask ->
            Common.DillonkearnsElmPages

        LamderaProgramTestCmd ->
            Common.LamderaProgramTest

        LamderaProgramTestCmdRisky ->
            Common.LamderaProgramTest

        LamderaProgramTestCmdRecord ->
            Common.LamderaProgramTest

        LamderaProgramTestTask ->
            Common.LamderaProgramTest

        LamderaProgramTestTaskRisky ->
            Common.LamderaProgramTest

        LamderaProgramTestTaskRecord ->
            Common.LamderaProgramTest


{-| One or multiple servers that the API will connect to.
-}
type Server
    = Default
    | Single String
    | Multiple (Dict.Dict String String)


{-| A custom `format` for basic types.
-}
type alias Format =
    { basicType : Common.BasicType
    , format : String
    , encode : Elm.Expression -> Elm.Expression
    , decoder : Elm.Expression
    , toParamString : Elm.Expression -> Elm.Expression
    , annotation : Elm.Annotation.Annotation
    , sharedDeclarations : List ( String, { value : Elm.Expression, group : String } )
    , requiresPackages : List String
    , example : Json.Encode.Value
    }


{-| An input path. Can be either a local file or an URL.
-}
type Path
    = File String -- swagger.json ./swagger.json /folder/swagger.json
    | Url Url.Url -- https://petstore3.swagger.io/api/v3/openapi.json


{-| Builds a `Path`. If the file is a valid URL, it will be used as such, otherwise it will be interpreted as a local file path.
-}
pathFromString : String -> Path
pathFromString path =
    case Url.fromString path of
        Just url ->
            Url url

        Nothing ->
            File path


{-| Convert a `Path` back to its string form.
-}
pathToString : Path -> String
pathToString pathType =
    case pathType of
        File file ->
            file

        Url url ->
            Url.toString url


{-| Create an empty `Config` with no inputs and a given output directory.

The default options are to:

  - run elm-format;
  - ask before converting Swagger specs to OpenAPI specs;
  - fail rather than generating `Debug.todo` or skipping unimplemented paths.

-}
init : String -> Config
init initialOutputDirectory =
    { inputs = []
    , outputDirectory = initialOutputDirectory
    , generateTodos = False
    , autoConvertSwagger = AskBeforeConversion
    , swaggerConversionUrl = "https://converter.swagger.io/api/convert"
    , swaggerConversionCommand = Nothing
    , staticFormats = defaultFormats
    , dynamicFormats = \_ -> []
    , noElmFormat = False
    , keepGoing = False
    }
        |> Config


{-| Create a default `Input` from a path.

The generated module name will be derived from the OpenAPI title unless you
override it later.

-}
inputFrom : Path -> Input
inputFrom path =
    { oasPath = path
    , outputModuleName = Nothing
    , server = Default
    , overrides = []
    , writeMergedTo = Nothing
    , responseVersionCheck = Nothing
    , effectTypes = [ ElmHttpCmd, ElmHttpTask ]
    , warnOnMissingEnums = False
    }
        |> Input



-------------
-- Formats --
-------------


{-| The built-in formats:

  - `date-time`
  - `date`
  - `uri`
  - `uuid`
  - `byte`
  - `password`

-}
defaultFormats : List Format
defaultFormats =
    [ dateTimeFormat
    , dateFormat
    , uriFormat
    , uuidFormat
    , byteFormat
    , passwordFormat
    ]


dateTimeFormat : Format
dateTimeFormat =
    let
        toString : Elm.Expression -> Elm.Expression
        toString instant =
            Gen.Rfc3339.make_.dateTimeOffset
                (Elm.record
                    [ ( "instant", instant )
                    , ( "offset"
                      , Elm.record
                            [ ( "hour", Elm.int 0 )
                            , ( "minute", Elm.int 0 )
                            ]
                      )
                    ]
                )
                |> Gen.Rfc3339.toString
    in
    { basicType = Common.String
    , format = "date-time"
    , annotation = Gen.Time.annotation_.posix
    , encode =
        \instant ->
            instant
                |> toString
                |> Gen.Json.Encode.call_.string
    , decoder =
        Gen.Json.Decode.string
            |> Gen.Json.Decode.andThen
                (\raw ->
                    Gen.Result.caseOf_.result
                        (Gen.Parser.Advanced.call_.run Gen.Rfc3339.dateTimeOffsetParser raw)
                        { ok = \record -> Gen.Json.Decode.succeed (Elm.get "instant" record)

                        -- TODO: improve error message
                        , err = \_ -> Gen.Json.Decode.fail "Invalid RFC-3339 date-time"
                        }
                )
    , toParamString = toString
    , sharedDeclarations = []
    , requiresPackages =
        [ "elm/parser"
        , "elm/time"
        , "justinmimbs/time-extra"
        , "wolfadex/elm-rfc3339"
        ]
    , example = Json.Encode.string "1789-07-21T12:00:00+01:00"
    }


dateFormat : Format
dateFormat =
    { basicType = Common.String
    , format = "date"
    , annotation = Gen.Date.annotation_.date
    , encode =
        \date ->
            date
                |> Gen.Date.toIsoString
                |> Gen.Json.Encode.call_.string
    , toParamString = Gen.Date.toIsoString
    , decoder =
        Gen.Json.Decode.string
            |> Gen.Json.Decode.andThen
                (\raw ->
                    Gen.Result.caseOf_.result
                        (Gen.Date.call_.fromIsoString raw)
                        { ok = Gen.Json.Decode.succeed
                        , err = Gen.Json.Decode.call_.fail
                        }
                )
    , sharedDeclarations = []
    , requiresPackages = [ "justinmimbs/date" ]
    , example = Json.Encode.string "1789-07-21"
    }


uuidFormat : Format
uuidFormat =
    { basicType = Common.String
    , format = "uuid"
    , annotation = Gen.Uuid.annotation_.uuid
    , encode =
        \url ->
            url
                |> Gen.Uuid.toString
                |> Gen.Json.Encode.call_.string
    , toParamString = Gen.Uuid.toString
    , decoder =
        Gen.Json.Decode.string
            |> Gen.Json.Decode.andThen
                (\raw ->
                    Gen.Maybe.caseOf_.maybe
                        (Gen.Uuid.call_.fromString raw)
                        { just = Gen.Json.Decode.succeed
                        , nothing =
                            Gen.Json.Decode.call_.fail
                                (Elm.Op.append raw (Elm.string " is not a valid UUID"))
                        }
                )
    , sharedDeclarations = []
    , requiresPackages = [ "cachix/elm-uuid" ]
    , example = Json.Encode.string "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"
    }


uriFormat : Format
uriFormat =
    { basicType = Common.String
    , format = "uri"
    , annotation = Gen.Url.annotation_.url
    , encode =
        \url ->
            url
                |> Gen.Url.toString
                |> Gen.Json.Encode.call_.string
    , toParamString = Gen.Url.toString
    , decoder =
        Gen.Json.Decode.string
            |> Gen.Json.Decode.andThen
                (\raw ->
                    Gen.Maybe.caseOf_.maybe
                        (Gen.Url.call_.fromString raw)
                        { just = Gen.Json.Decode.succeed
                        , nothing =
                            Gen.Json.Decode.call_.fail
                                (Elm.Op.append raw (Elm.string " is not a valid URL"))
                        }
                )
    , sharedDeclarations = []
    , requiresPackages = [ "justinmimbs/date" ]
    , example = Json.Encode.string "https://en.wikipedia.org"
    }


byteFormat : Format
byteFormat =
    { basicType = Common.String
    , format = "byte"
    , annotation = Gen.Bytes.annotation_.bytes
    , encode =
        \bytes ->
            Gen.Base64.fromBytes bytes
                |> Gen.Maybe.withDefault (Elm.string "")
                |> Gen.Json.Encode.call_.string
    , toParamString =
        \bytes ->
            Gen.Base64.fromBytes bytes
                |> Gen.Maybe.withDefault (Elm.string "")
    , decoder =
        Gen.Json.Decode.string
            |> Gen.Json.Decode.andThen
                (\raw ->
                    Elm.Case.maybe (Gen.Base64.call_.toBytes raw)
                        { just = ( "bytes", Gen.Json.Decode.succeed )
                        , nothing = Gen.Json.Decode.fail "Invalid base64 data"
                        }
                )
    , sharedDeclarations = []
    , requiresPackages = [ Common.base64PackageName ]
    , example = Json.Encode.string "<bytes>"
    }


passwordFormat : Format
passwordFormat =
    { basicType = Common.String
    , format = "password"
    , annotation = Elm.Annotation.string
    , encode = Gen.Json.Encode.call_.string
    , decoder =
        Gen.Json.Decode.string
    , toParamString = identity
    , sharedDeclarations = []
    , requiresPackages = []
    , example = Json.Encode.string "hunter2"
    }



-------------
-- Setters --
-------------


{-| Set the effect types to generate for this input.
-}
withEffectTypes : List EffectType -> Input -> Input
withEffectTypes effectTypes (Input input) =
    Input { input | effectTypes = effectTypes }


{-| Override the generated module namespace for this input.
-}
withOutputModuleName : List String -> Input -> Input
withOutputModuleName moduleName (Input input) =
    Input { input | outputModuleName = Just moduleName }


{-| Attach override files that should be merged into the input spec before generation.
-}
withOverrides : List Path -> Input -> Input
withOverrides newOverrides (Input input) =
    Input { input | overrides = newOverrides }


{-| Configure whether unsupported branches should generate `Debug.todo`.
-}
withGenerateTodos : Bool -> Config -> Config
withGenerateTodos generateTodos (Config config) =
    Config { config | generateTodos = generateTodos }


{-| Choose how Swagger inputs should be converted to OpenAPI.
-}
withAutoConvertSwagger : AutoConvertSwagger -> Config -> Config
withAutoConvertSwagger newAutoConvertSwagger (Config config) =
    Config { config | autoConvertSwagger = newAutoConvertSwagger }


{-| Set the URL used for remote Swagger-to-OpenAPI conversion.
-}
withSwaggerConversionUrl : String -> Config -> Config
withSwaggerConversionUrl newSwaggerConversionUrl (Config config) =
    Config { config | swaggerConversionUrl = newSwaggerConversionUrl }


{-| Use a custom command instead of the default remote Swagger conversion service.
-}
withSwaggerConversionCommand : { command : String, args : List String } -> Config -> Config
withSwaggerConversionCommand newSwaggerConversionCommand (Config config) =
    Config { config | swaggerConversionCommand = Just newSwaggerConversionCommand }


{-| Override the server configuration for generated requests from this input.
-}
withServer : Server -> Input -> Input
withServer newServer (Input input) =
    Input { input | server = newServer }


{-| Write the merged OpenAPI document for this input to the given path.
-}
withWriteMergedTo : String -> Input -> Input
withWriteMergedTo newWriteMergedTo (Input input) =
    Input { input | writeMergedTo = Just newWriteMergedTo }


{-| Expose the given response version header in generated error helpers for this input.
-}
withResponseVersionCheck : ResponseVersionCheck -> Input -> Input
withResponseVersionCheck newResponseVersionCheck (Input input) =
    Input { input | responseVersionCheck = Just newResponseVersionCheck }


{-| Enable or disable warnings for enums that cannot be represented precisely.
-}
withWarnOnMissingEnums : Bool -> Input -> Input
withWarnOnMissingEnums newWarnOnMissingEnums (Input input) =
    Input { input | warnOnMissingEnums = newWarnOnMissingEnums }


{-| Add one custom format to the global configuration.
-}
withFormat : Format -> Config -> Config
withFormat newFormat (Config config) =
    Config { config | staticFormats = newFormat :: config.staticFormats }


{-| Add custom formats derived from the formats already present in the OpenAPI inputs.
-}
withFormats :
    (List { format : String, basicType : Common.BasicType } -> List Format)
    -> Config
    -> Config
withFormats newFormat (Config config) =
    Config { config | dynamicFormats = \input -> newFormat input ++ config.dynamicFormats input }


{-| Add one input specification to the generator configuration.
-}
withInput : Input -> Config -> Config
withInput input (Config config) =
    Config { config | inputs = input :: config.inputs }


{-| Skip running `elm-format` on generated files when set to `True`.
-}
withNoElmFormat : Bool -> Config -> Config
withNoElmFormat newNoElmFormat (Config config) =
    Config { config | noElmFormat = newNoElmFormat }


{-| Continue generation after non-fatal issues by collecting warnings where possible.
-}
withKeepGoing : Bool -> Config -> Config
withKeepGoing newKeepGoing (Config config) =
    Config { config | keepGoing = newKeepGoing }



-------------
-- Getters --
-------------


{-| The configured Swagger conversion URL.
-}
swaggerConversionUrl : Config -> String
swaggerConversionUrl (Config config) =
    config.swaggerConversionUrl


{-| The custom Swagger conversion command, if one has been configured.
-}
swaggerConversionCommand : Config -> Maybe { command : String, args : List String }
swaggerConversionCommand (Config config) =
    config.swaggerConversionCommand


{-| How Swagger conversion should be handled.
-}
autoConvertSwagger : Config -> AutoConvertSwagger
autoConvertSwagger (Config config) =
    config.autoConvertSwagger


{-| The output directory for generated files.
-}
outputDirectory : Config -> String
outputDirectory (Config config) =
    config.outputDirectory


{-| The configured input specs in insertion order.
-}
inputs : Config -> List Input
inputs (Config config) =
    List.reverse config.inputs


{-| Whether generated files should skip `elm-format`.
-}
noElmFormat : Config -> Bool
noElmFormat (Config config) =
    config.noElmFormat


{-| Whether generation should continue after recoverable problems.
-}
keepGoing : Config -> Bool
keepGoing (Config config) =
    config.keepGoing


{-| The source path or URL for this input spec.
-}
oasPath : Input -> Path
oasPath (Input input) =
    input.oasPath


{-| The optional path where the merged spec should be written.
-}
writeMergedTo : Input -> Maybe String
writeMergedTo (Input input) =
    input.writeMergedTo


{-| The configured response version header extraction, if enabled.
-}
responseVersionCheck : Input -> Maybe ResponseVersionCheck
responseVersionCheck (Input input) =
    input.responseVersionCheck


{-| Override files to merge into the input spec before generation.
-}
overrides : Input -> List Path
overrides (Input input) =
    input.overrides



------------
-- Output --
------------


{-| The normalized generation settings derived from a `Config` and parsed inputs.
-}
type alias Generate =
    { namespace : List String
    , generateTodos : Bool
    , effectTypes : List EffectType
    , server : Server
    , formats : List Format
    , warnOnMissingEnums : Bool
    , keepGoing : Bool
    }


{-| Convert the full configuration and parsed OpenAPI inputs into per-input generation settings.
-}
toGenerationConfig :
    List { format : String, basicType : Common.BasicType }
    -> Config
    -> List ( Input, OpenApi.OpenApi )
    ->
        List
            ( Generate
            , OpenApi.OpenApi
            )
toGenerationConfig formatsInput (Config config) augmentedInputs =
    List.map
        (\( Input input, spec ) ->
            ( { namespace =
                    case input.outputModuleName of
                        Just modName ->
                            modName

                        Nothing ->
                            spec
                                |> OpenApi.info
                                |> OpenApi.Info.title
                                |> Utils.sanitizeModuleName
                                |> Maybe.withDefault "Api"
                                |> List.singleton
              , generateTodos = config.generateTodos
              , effectTypes = input.effectTypes
              , server = input.server
              , warnOnMissingEnums = input.warnOnMissingEnums
              , formats = config.staticFormats ++ config.dynamicFormats formatsInput
              , keepGoing = config.keepGoing
              }
            , spec
            )
        )
        augmentedInputs
