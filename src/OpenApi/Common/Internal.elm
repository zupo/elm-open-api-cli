module OpenApi.Common.Internal exposing (CommonSubmodule, ElmHttpBase64Submodule, ElmHttpSubmodule, Error, LamderaProgramTestBase64Submodule, LamderaProgramTestSubmodule, Nullable, annotation_, commonSubmodule, declarations, elmHttpBase64Submodule, elmHttpSubmodule, lamderaProgramTestBase64Submodule, lamderaProgramTestSubmodule, make_)

import Common
import Elm
import Elm.Annotation
import Elm.Arg
import Elm.Case
import Elm.Declare
import Elm.Declare.Extra
import Elm.Extra
import Elm.Op
import Gen.Base64
import Gen.Bytes
import Gen.Bytes.Decode
import Gen.Dict
import Gen.Effect.Http
import Gen.Http
import Gen.Json.Decode
import Gen.Maybe
import Gen.Result
import Gen.String
import OpenApi.Config


annotation_ :
    { error : Elm.Annotation.Annotation -> Elm.Annotation.Annotation -> Elm.Annotation.Annotation
    , nullable : Elm.Annotation.Annotation -> Elm.Annotation.Annotation
    }
annotation_ =
    { error = \err ok -> Elm.Annotation.namedWith Common.commonModuleName "Error" [ err, ok ]
    , nullable = \t -> Elm.Annotation.namedWith Common.commonModuleName "Nullable" [ t ]
    }


make_ :
    { null : Elm.Expression
    , present : Elm.Expression -> Elm.Expression
    }
make_ =
    { null = commonSubmodule.call.nullable.make_.null
    , present = commonSubmodule.call.nullable.make_.present
    }


errorAnnotation : Elm.Annotation.Annotation -> Elm.Annotation.Annotation
errorAnnotation t =
    annotation_.error (Elm.Annotation.var "err") t


declarations :
    { a
        | requiresBase64 : Bool
        , effectTypes : List OpenApi.Config.EffectType
        , responseVersionCheck : Maybe OpenApi.Config.ResponseVersionCheck
    }
    -> List { declaration : Elm.Declaration, group : String }
declarations { requiresBase64, effectTypes, responseVersionCheck } =
    let
        requiresElmHttp : Bool
        requiresElmHttp =
            List.any
                (\effectType -> OpenApi.Config.effectTypeToPackage effectType == Common.ElmHttp)
                effectTypes

        requiresLamderaProgramTest : Bool
        requiresLamderaProgramTest =
            List.any
                (\effectType -> OpenApi.Config.effectTypeToPackage effectType == Common.LamderaProgramTest)
                effectTypes

        elmHttp : List { declaration : Elm.Declaration, group : String }
        elmHttp =
            group "elm/http" requiresElmHttp elmHttpSubmodule

        elmHttpBase64 : List { declaration : Elm.Declaration, group : String }
        elmHttpBase64 =
            group "elm/http" (requiresElmHttp && requiresBase64) elmHttpBase64Submodule

        lamderaProgramTest : List { declaration : Elm.Declaration, group : String }
        lamderaProgramTest =
            group "lamdera/program-test" requiresLamderaProgramTest lamderaProgramTestSubmodule

        lamderaProgramTestBase64 : List { declaration : Elm.Declaration, group : String }
        lamderaProgramTestBase64 =
            group "lamdera/program-test" (requiresLamderaProgramTest && requiresBase64) lamderaProgramTestBase64Submodule

        common : List { declaration : Elm.Declaration, group : String }
        common =
            group "Common" True commonSubmodule
                ++ responseVersionDeclarations responseVersionCheck

        group :
            String
            -> Bool
            -> { sub | declarations : List Elm.Declaration }
            -> List { declaration : Elm.Declaration, group : String }
        group name condition submodule =
            if condition then
                List.map
                    (\declaration ->
                        { declaration = declaration
                        , group = name
                        }
                    )
                    submodule.declarations

            else
                []
    in
    elmHttp ++ elmHttpBase64 ++ lamderaProgramTest ++ lamderaProgramTestBase64 ++ common


responseVersionDeclarations :
    Maybe OpenApi.Config.ResponseVersionCheck
    -> List { declaration : Elm.Declaration, group : String }
responseVersionDeclarations maybeResponseVersionCheck =
    [ { declaration = responseVersionAlias
      , group = "Types"
      }
    , { declaration = responseWithVersionAlias
      , group = "Types"
      }
    , { declaration = responseVersionFromMetadata maybeResponseVersionCheck
      , group = "Common"
      }
    ]
        ++ (case maybeResponseVersionCheck of
                Nothing ->
                    []

                Just responseVersionCheck ->
                    [ { declaration = responseVersionFromError responseVersionCheck
                      , group = "Common"
                      }
                    ]
           )


responseVersionAlias : Elm.Declaration
responseVersionAlias =
    Elm.alias "ResponseVersion"
        (Elm.Annotation.record
            [ ( "headerName", Elm.Annotation.string )
            , ( "responseVersion", Elm.Annotation.string )
            ]
        )
        |> Elm.withDocumentation "The response version header extracted from an API error."
        |> Elm.expose


responseWithVersionAlias : Elm.Declaration
responseWithVersionAlias =
    Elm.alias "ResponseWithVersion"
        (Elm.Annotation.record
            [ ( "value", Elm.Annotation.var "value" )
            , ( "responseVersion"
              , Elm.Annotation.maybe
                    (Elm.Annotation.namedWith Common.commonModuleName "ResponseVersion" [])
              )
            ]
        )
        |> Elm.withDocumentation "A value together with any observed response version header."
        |> Elm.expose


responseVersionFromError : OpenApi.Config.ResponseVersionCheck -> Elm.Declaration
responseVersionFromError { headerName } =
    let
        responseVersionAnnotation : Elm.Annotation.Annotation
        responseVersionAnnotation =
            Elm.Annotation.namedWith Common.commonModuleName "ResponseVersion" []

        fromHeaders : Elm.Expression -> Elm.Expression
        fromHeaders headers =
            Gen.Dict.call_.foldl
                (Elm.fn3
                    (Elm.Arg.varWith "key" Elm.Annotation.string)
                    (Elm.Arg.varWith "value" Elm.Annotation.string)
                    (Elm.Arg.varWith "found" (Elm.Annotation.maybe responseVersionAnnotation))
                    (\key value found ->
                        Elm.Case.maybe found
                            { just = ( "match", Gen.Maybe.make_.just )
                            , nothing =
                                Elm.ifThen
                                    (Elm.Op.equal
                                        (Gen.String.call_.toLower key)
                                        (Gen.String.call_.toLower (Elm.string headerName))
                                    )
                                    (Gen.Maybe.make_.just
                                        (Elm.record
                                            [ ( "headerName", Elm.string headerName )
                                            , ( "responseVersion", value )
                                            ]
                                        )
                                    )
                                    Gen.Maybe.make_.nothing
                            }
                    )
                )
                Gen.Maybe.make_.nothing
                headers

        fromMetadata : Elm.Expression -> Elm.Expression
        fromMetadata metadata =
            fromHeaders (Elm.get "headers" metadata)
    in
    Elm.fn
        (Elm.Arg.varWith
            "err"
            (annotation_.error (Elm.Annotation.var "err") (Elm.Annotation.var "body"))
        )
        (\err ->
            error.case_ err
                { badUrl = \_ -> Gen.Maybe.make_.nothing
                , timeout = Gen.Maybe.make_.nothing
                , networkError = Gen.Maybe.make_.nothing
                , knownBadStatus = \_ _ -> Gen.Maybe.make_.nothing
                , unknownBadStatus = \metadata _ -> fromMetadata metadata
                , badErrorBody = \metadata _ -> fromMetadata metadata
                , badBody = \metadata _ -> fromMetadata metadata
                }
                |> Elm.withType (Elm.Annotation.maybe responseVersionAnnotation)
        )
        |> Elm.withType
            (Elm.Annotation.function
                [ annotation_.error (Elm.Annotation.var "err") (Elm.Annotation.var "body") ]
                (Elm.Annotation.maybe responseVersionAnnotation)
            )
        |> Elm.declaration "responseVersionFromError"
        |> Elm.withDocumentation
            ("Extract the configured response version header from an API error.\n\n"
                ++ "This is useful when your application wants to forward the server's\n"
                ++ "response version to JavaScript, a port, or shared app state.\n"
                ++ "Any comparison or reload behavior is handled by your application."
            )
        |> Elm.expose


responseVersionFromMetadata : Maybe OpenApi.Config.ResponseVersionCheck -> Elm.Declaration
responseVersionFromMetadata maybeResponseVersionCheck =
    let
        responseVersionAnnotation : Elm.Annotation.Annotation
        responseVersionAnnotation =
            Elm.Annotation.namedWith Common.commonModuleName "ResponseVersion" []

        fromHeaders : Elm.Expression -> Elm.Expression
        fromHeaders headers =
            case maybeResponseVersionCheck of
                Nothing ->
                    Gen.Maybe.make_.nothing

                Just { headerName } ->
                    Gen.Dict.call_.foldl
                        (Elm.fn3
                            (Elm.Arg.varWith "key" Elm.Annotation.string)
                            (Elm.Arg.varWith "value" Elm.Annotation.string)
                            (Elm.Arg.varWith "found" (Elm.Annotation.maybe responseVersionAnnotation))
                            (\key value found ->
                                Elm.Case.maybe found
                                    { just = ( "match", Gen.Maybe.make_.just )
                                    , nothing =
                                        Elm.ifThen
                                            (Elm.Op.equal
                                                (Gen.String.call_.toLower key)
                                                (Gen.String.call_.toLower (Elm.string headerName))
                                            )
                                            (Gen.Maybe.make_.just
                                                (Elm.record
                                                    [ ( "headerName", Elm.string headerName )
                                                    , ( "responseVersion", value )
                                                    ]
                                                )
                                            )
                                            Gen.Maybe.make_.nothing
                                    }
                            )
                        )
                        Gen.Maybe.make_.nothing
                        headers
    in
    Elm.fn
        (Elm.Arg.varWith "metadata" Gen.Http.annotation_.metadata)
        (\metadata ->
            fromHeaders (Elm.get "headers" metadata)
                |> Elm.withType (Elm.Annotation.maybe responseVersionAnnotation)
        )
        |> Elm.withType
            (Elm.Annotation.function
                [ Gen.Http.annotation_.metadata ]
                (Elm.Annotation.maybe responseVersionAnnotation)
            )
        |> Elm.declaration "responseVersionFromMetadata"
        |> Elm.withDocumentation "Extract the configured response version header from response metadata."


type alias ElmHttpSubmodule =
    { expectJsonCustom : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , jsonResolverCustom : Elm.Expression -> Elm.Expression -> Elm.Expression
    , expectStringCustom : Elm.Expression -> Elm.Expression -> Elm.Expression
    , stringResolverCustom : Elm.Expression -> Elm.Expression
    , expectBytesCustom : Elm.Expression -> Elm.Expression -> Elm.Expression
    , bytesResolverCustom : Elm.Expression -> Elm.Expression
    }


elmHttpSubmodule : Elm.Declare.Module ElmHttpSubmodule
elmHttpSubmodule =
    Elm.Declare.module_ Common.commonModuleName ElmHttpSubmodule
        |> Elm.Declare.with expectJsonCustom
        |> Elm.Declare.with jsonResolverCustom
        |> Elm.Declare.with expectStringCustom
        |> Elm.Declare.with stringResolverCustom
        |> Elm.Declare.with expectBytesCustom
        |> Elm.Declare.with bytesResolverCustom
        |> Elm.Declare.withUnexposed responseToResult
        |> Elm.Declare.withUnexposed responseVersionFromResponse
        |> Elm.Declare.withUnexposed wrapResultWithResponseVersion


type alias ElmHttpBase64Submodule =
    { expectBase64Custom : Elm.Expression -> Elm.Expression -> Elm.Expression
    , base64ResolverCustom : Elm.Expression -> Elm.Expression
    }


elmHttpBase64Submodule : Elm.Declare.Module ElmHttpBase64Submodule
elmHttpBase64Submodule =
    Elm.Declare.module_ Common.commonModuleName ElmHttpBase64Submodule
        |> Elm.Declare.with expectBase64Custom
        |> Elm.Declare.with base64ResolverCustom


expectJsonCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
expectJsonCustom =
    outerExpectJsonCustom "expectJsonCustom"
        (\errorDecoders successDecoder toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.apply (Elm.val "responseVersionFromResponse") [ response ])
                        (responseToResultWrapped
                            errorDecoders
                            identity
                            (innerExpectJsonCustom successDecoder)
                            response
                        )
            in
            Gen.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


jsonResolverCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
jsonResolverCustom =
    outerJsonResolverCustom "jsonResolverCustom" <|
        \errorDecoders successDecoder ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultWrapped
                        errorDecoders
                        identity
                        (innerExpectJsonCustom successDecoder)
                        response
            in
            Gen.Http.stringResolver toResult
                |> Elm.withType (Gen.Http.annotation_.resolver (errorAnnotation Elm.Annotation.string) (Elm.Annotation.var "success"))


expectStringCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectStringCustom =
    outerExpectStringCustom Elm.Annotation.string
        "expectStringCustom"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.apply (Elm.val "responseVersionFromResponse") [ response ])
                        (responseToResultWrapped
                            errorDecoders
                            identity
                            (always Gen.Result.make_.ok)
                            response
                        )
            in
            Gen.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


stringResolverCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
stringResolverCustom =
    outerRawResolverCustom "stringResolverCustom" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultWrapped
                        errorDecoders
                        identity
                        (always Gen.Result.make_.ok)
                        response
            in
            Gen.Http.stringResolver toResult
                |> Elm.withType (Gen.Http.annotation_.resolver (errorAnnotation Elm.Annotation.string) Elm.Annotation.string)


expectBytesCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectBytesCustom =
    outerExpectBytesCustom "expectBytesCustom"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.apply (Elm.val "responseVersionFromResponse") [ response ])
                        (responseToResultWrapped
                            errorDecoders
                            bytesToString
                            (always Gen.Result.make_.ok)
                            response
                        )
            in
            Gen.Http.expectBytesResponse toMsg toPayload
                |> Elm.withType (Gen.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


bytesResolverCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
bytesResolverCustom =
    outerRawResolverCustom "bytesResolverCustom" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultWrapped
                        errorDecoders
                        bytesToString
                        (always Gen.Result.make_.ok)
                        response
            in
            Gen.Http.bytesResolver toResult
                |> Elm.withType (Gen.Http.annotation_.resolver (errorAnnotation Gen.Bytes.annotation_.bytes) Gen.Bytes.annotation_.bytes)


expectBase64Custom : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectBase64Custom =
    outerExpectStringCustom Gen.Bytes.annotation_.bytes
        "expectBase64Custom"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.apply (Elm.val "responseVersionFromResponse") [ response ])
                        (responseToResultWrapped
                            errorDecoders
                            identity
                            (\metadata body ->
                                body
                                    |> Gen.Base64.call_.toBytes
                                    |> Gen.Result.fromMaybe (error.make_.badBody metadata body)
                            )
                            response
                        )
            in
            Gen.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


base64ResolverCustom : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
base64ResolverCustom =
    outerRawResolverCustom "base64ResolverCustom" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultWrapped
                        errorDecoders
                        identity
                        (\metadata body ->
                            body
                                |> Gen.Base64.call_.toBytes
                                |> Gen.Result.fromMaybe (error.make_.badBody metadata body)
                        )
                        response
            in
            Gen.Http.stringResolver toResult
                |> Elm.withType (Gen.Http.annotation_.resolver (errorAnnotation Elm.Annotation.string) Gen.Bytes.annotation_.bytes)


responseToResultWrapped :
    Elm.Expression
    -> (Elm.Expression -> Elm.Expression)
    -> (Elm.Expression -> Elm.Expression -> Elm.Expression)
    -> Elm.Expression
    -> Elm.Expression
responseToResultWrapped errorDecoders bodyToString onSuccess response =
    responseToResult.call
        errorDecoders
        (Elm.Extra.functionReduced "body" bodyToString)
        (Elm.fn2 (Elm.Arg.var "metadata") (Elm.Arg.var "body") onSuccess)
        response


responseVersionFromResponse : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
responseVersionFromResponse =
    Elm.Declare.fn "responseVersionFromResponse"
        (Elm.Arg.varWith "response" (Gen.Http.annotation_.response (Elm.Annotation.var "body")))
        (\response ->
            Gen.Http.caseOf_.response response
                { badUrl_ = \_ -> Gen.Maybe.make_.nothing
                , timeout_ = Gen.Maybe.make_.nothing
                , networkError_ = Gen.Maybe.make_.nothing
                , badStatus_ = \metadata _ -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                , goodStatus_ = \metadata _ -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                }
                |> Elm.withType
                    (Elm.Annotation.maybe
                        (Elm.Annotation.namedWith Common.commonModuleName "ResponseVersion" [])
                    )
        )


wrapResultWithResponseVersion : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
wrapResultWithResponseVersion =
    Elm.Declare.fn2 "wrapResultWithResponseVersion"
        (Elm.Arg.varWith
            "responseVersion"
            (Elm.Annotation.maybe
                (Elm.Annotation.namedWith Common.commonModuleName "ResponseVersion" [])
            )
        )
        (Elm.Arg.varWith
            "result"
            (Elm.Annotation.result (Elm.Annotation.var "err") (Elm.Annotation.var "value"))
        )
        (\responseVersion result ->
            Elm.apply
                Gen.Result.values_.mapError
                [ Elm.fn
                    (Elm.Arg.varWith "err" (Elm.Annotation.var "err"))
                    (\err ->
                        Elm.record
                            [ ( "value", err )
                            , ( "responseVersion", responseVersion )
                            ]
                    )
                , Elm.apply
                    Gen.Result.values_.map
                    [ Elm.fn
                        (Elm.Arg.varWith "value" (Elm.Annotation.var "value"))
                        (\value ->
                            Elm.record
                                [ ( "value", value )
                                , ( "responseVersion", responseVersion )
                                ]
                        )
                    , result
                    ]
                ]
                |> Elm.withType
                    (Elm.Annotation.result
                        (Elm.Annotation.namedWith Common.commonModuleName "ResponseWithVersion" [ Elm.Annotation.var "err" ])
                        (Elm.Annotation.namedWith Common.commonModuleName "ResponseWithVersion" [ Elm.Annotation.var "value" ])
                    )
        )


responseToResult : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
responseToResult =
    Elm.Declare.fn4 "responseToResult"
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "bodyToString"
            (Elm.Annotation.function
                [ Elm.Annotation.var "body" ]
                Elm.Annotation.string
            )
        )
        (Elm.Arg.varWith "onSuccess"
            (Elm.Annotation.function
                [ Gen.Http.annotation_.metadata
                , Elm.Annotation.var "body"
                ]
                (Elm.Annotation.result
                    (error.annotation (Elm.Annotation.var "err") (Elm.Annotation.var "body"))
                    (Elm.Annotation.var "value")
                )
            )
        )
        (Elm.Arg.varWith "response"
            (Gen.Http.annotation_.response
                (Elm.Annotation.var "body")
            )
        )
        (\errorDecoders bodyToString onSuccess response ->
            Gen.Http.caseOf_.response response
                { badUrl_ = \url -> Gen.Result.make_.err (error.make_.badUrl url)
                , timeout_ = Gen.Result.make_.err error.make_.timeout
                , networkError_ = Gen.Result.make_.err error.make_.networkError
                , badStatus_ =
                    \metadata body ->
                        Elm.Case.maybe
                            (Gen.Dict.get (Gen.String.call_.fromInt (Elm.get "statusCode" metadata)) errorDecoders)
                            { nothing =
                                Gen.Result.make_.err
                                    (error.make_.unknownBadStatus metadata body)
                            , just =
                                ( "err"
                                , \errorDecoder ->
                                    Elm.Case.result
                                        (Gen.Json.Decode.call_.decodeString errorDecoder
                                            (Elm.apply bodyToString [ body ])
                                        )
                                        { ok =
                                            ( "res"
                                            , \x ->
                                                Gen.Result.make_.err
                                                    (error.make_.knownBadStatus (Elm.get "statusCode" metadata) x)
                                            )
                                        , err =
                                            ( "_"
                                            , \_ ->
                                                Gen.Result.make_.err
                                                    (error.make_.badErrorBody metadata body)
                                            )
                                        }
                                )
                            }
                , goodStatus_ = \metadata body -> Elm.apply onSuccess [ metadata, body ]
                }
                |> Elm.withType
                    (Elm.Annotation.result
                        (error.annotation (Elm.Annotation.var "err") (Elm.Annotation.var "body"))
                        (Elm.Annotation.var "value")
                    )
        )


type alias LamderaProgramTestSubmodule =
    { expectJsonCustomEffect : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , jsonResolverCustomEffect : Elm.Expression -> Elm.Expression -> Elm.Expression
    , expectStringCustomEffect : Elm.Expression -> Elm.Expression -> Elm.Expression
    , stringResolverCustomEffect : Elm.Expression -> Elm.Expression
    , expectBytesCustomEffect : Elm.Expression -> Elm.Expression -> Elm.Expression
    , bytesResolverCustomEffect : Elm.Expression -> Elm.Expression
    }


lamderaProgramTestSubmodule : Elm.Declare.Module LamderaProgramTestSubmodule
lamderaProgramTestSubmodule =
    Elm.Declare.module_ Common.commonModuleName LamderaProgramTestSubmodule
        |> Elm.Declare.with expectJsonCustomEffect
        |> Elm.Declare.with jsonResolverCustomEffect
        |> Elm.Declare.with expectStringCustomEffect
        |> Elm.Declare.with stringResolverCustomEffect
        |> Elm.Declare.with expectBytesCustomEffect
        |> Elm.Declare.with bytesResolverCustomEffect
        |> Elm.Declare.withUnexposed responseToResultEffect
        |> Elm.Declare.withUnexposed wrapResultWithResponseVersion


type alias LamderaProgramTestBase64Submodule =
    { expectBase64CustomEffect : Elm.Expression -> Elm.Expression -> Elm.Expression
    , base64ResolverCustomEffect : Elm.Expression -> Elm.Expression
    }


lamderaProgramTestBase64Submodule : Elm.Declare.Module LamderaProgramTestBase64Submodule
lamderaProgramTestBase64Submodule =
    Elm.Declare.module_ Common.commonModuleName LamderaProgramTestBase64Submodule
        |> Elm.Declare.with expectBase64CustomEffect
        |> Elm.Declare.with base64ResolverCustomEffect


expectJsonCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
expectJsonCustomEffect =
    outerExpectJsonCustom "expectJsonCustomEffect"
        (\errorDecoders successDecoder toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.Case.maybe
                            (Elm.get "metadata" response)
                            { just =
                                ( "metadata"
                                , \metadata -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                                )
                            , nothing = Gen.Maybe.make_.nothing
                            }
                        )
                        (responseToResultEffectWrapped
                            errorDecoders
                            identity
                            (innerExpectJsonCustom successDecoder)
                            response
                        )
            in
            Gen.Effect.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Effect.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


jsonResolverCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
jsonResolverCustomEffect =
    outerJsonResolverCustom "jsonResolverCustomEffect" <|
        \errorDecoders successDecoder ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultEffectWrapped errorDecoders identity (innerExpectJsonCustom successDecoder) response
            in
            Gen.Effect.Http.stringResolver toResult
                |> Elm.withType (Gen.Effect.Http.annotation_.resolver (Elm.Annotation.var "restrictions") (errorAnnotation Elm.Annotation.string) (Elm.Annotation.var "success"))


expectBytesCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectBytesCustomEffect =
    outerExpectBytesCustom "expectBytesCustomEffect"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.Case.maybe
                            (Elm.get "metadata" response)
                            { just =
                                ( "metadata"
                                , \metadata -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                                )
                            , nothing = Gen.Maybe.make_.nothing
                            }
                        )
                        (responseToResultEffectWrapped
                            errorDecoders
                            bytesToString
                            (always Gen.Result.make_.ok)
                            response
                        )
            in
            Gen.Effect.Http.expectBytesResponse toMsg toPayload
                |> Elm.withType (Gen.Effect.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


bytesResolverCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
bytesResolverCustomEffect =
    outerRawResolverCustom "bytesResolverCustomEffect" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultEffectWrapped
                        errorDecoders
                        bytesToString
                        (always Gen.Result.make_.ok)
                        response
            in
            Gen.Effect.Http.bytesResolver toResult
                |> Elm.withType (Gen.Effect.Http.annotation_.resolver (Elm.Annotation.var "restrictions") (errorAnnotation Gen.Bytes.annotation_.bytes) Gen.Bytes.annotation_.bytes)


expectStringCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectStringCustomEffect =
    outerExpectStringCustom Elm.Annotation.string
        "expectStringCustomEffect"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.Case.maybe
                            (Elm.get "metadata" response)
                            { just =
                                ( "metadata"
                                , \metadata -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                                )
                            , nothing = Gen.Maybe.make_.nothing
                            }
                        )
                        (responseToResultEffectWrapped
                            errorDecoders
                            identity
                            (always Gen.Result.make_.ok)
                            response
                        )
            in
            Gen.Effect.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Effect.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


stringResolverCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
stringResolverCustomEffect =
    outerRawResolverCustom "stringResolverCustomEffect" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultEffectWrapped
                        errorDecoders
                        identity
                        (always Gen.Result.make_.ok)
                        response
            in
            Gen.Effect.Http.stringResolver toResult
                |> Elm.withType (Gen.Effect.Http.annotation_.resolver (Elm.Annotation.var "restrictions") (errorAnnotation Elm.Annotation.string) Elm.Annotation.string)


expectBase64CustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
expectBase64CustomEffect =
    outerExpectStringCustom Gen.Bytes.annotation_.bytes
        "expectBase64CustomEffect"
        (\errorDecoders toMsg ->
            let
                toPayload : Elm.Expression -> Elm.Expression
                toPayload response =
                    wrapResultWithResponseVersion.call
                        (Elm.Case.maybe
                            (Elm.get "metadata" response)
                            { just =
                                ( "metadata"
                                , \metadata -> Elm.apply (Elm.val "responseVersionFromMetadata") [ metadata ]
                                )
                            , nothing = Gen.Maybe.make_.nothing
                            }
                        )
                        (responseToResultEffectWrapped
                            errorDecoders
                            identity
                            (\metadata body ->
                                body
                                    |> Gen.Base64.call_.toBytes
                                    |> Gen.Result.fromMaybe (error.make_.badBody metadata body)
                            )
                            response
                        )
            in
            Gen.Effect.Http.expectStringResponse toMsg toPayload
                |> Elm.withType (Gen.Effect.Http.annotation_.expect (Elm.Annotation.var "msg"))
        )


base64ResolverCustomEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
base64ResolverCustomEffect =
    outerRawResolverCustom "base64ResolverCustomEffect" <|
        \errorDecoders ->
            let
                toResult : Elm.Expression -> Elm.Expression
                toResult response =
                    responseToResultEffectWrapped
                        errorDecoders
                        identity
                        (\metadata body ->
                            body
                                |> Gen.Base64.call_.toBytes
                                |> Gen.Result.fromMaybe (error.make_.badBody metadata body)
                        )
                        response
            in
            Gen.Effect.Http.stringResolver toResult
                |> Elm.withType (Gen.Effect.Http.annotation_.resolver (Elm.Annotation.var "restrictions") (errorAnnotation Elm.Annotation.string) Gen.Bytes.annotation_.bytes)


responseToResultEffectWrapped :
    Elm.Expression
    -> (Elm.Expression -> Elm.Expression)
    -> (Elm.Expression -> Elm.Expression -> Elm.Expression)
    -> Elm.Expression
    -> Elm.Expression
responseToResultEffectWrapped errorDecoders bodyToString onSuccess response =
    responseToResultEffect.call
        errorDecoders
        (Elm.Extra.functionReduced "body" bodyToString)
        (Elm.fn2 (Elm.Arg.var "metadata") (Elm.Arg.var "body") onSuccess)
        response


responseToResultEffect : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
responseToResultEffect =
    Elm.Declare.fn4 "responseToResultEffect"
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "bodyToString"
            (Elm.Annotation.function
                [ Elm.Annotation.var "body" ]
                Elm.Annotation.string
            )
        )
        (Elm.Arg.varWith "onSuccess"
            (Elm.Annotation.function
                [ Gen.Effect.Http.annotation_.metadata
                , Elm.Annotation.var "body"
                ]
                (Elm.Annotation.result
                    (error.annotation (Elm.Annotation.var "err") (Elm.Annotation.var "body"))
                    (Elm.Annotation.var "value")
                )
            )
        )
        (Elm.Arg.varWith "response"
            (Gen.Effect.Http.annotation_.response
                (Elm.Annotation.var "body")
            )
        )
        (\errorDecoders bodyToString onSuccess response ->
            Gen.Effect.Http.caseOf_.response response
                { badUrl_ = \url -> Gen.Result.make_.err (error.make_.badUrl url)
                , timeout_ = Gen.Result.make_.err error.make_.timeout
                , networkError_ = Gen.Result.make_.err error.make_.networkError
                , badStatus_ =
                    \metadata body ->
                        Elm.Case.maybe
                            (Gen.Dict.get (Gen.String.call_.fromInt (Elm.get "statusCode" metadata)) errorDecoders)
                            { nothing =
                                Gen.Result.make_.err
                                    (error.make_.unknownBadStatus metadata body)
                            , just =
                                ( "err"
                                , \errorDecoder ->
                                    Elm.Case.result
                                        (Gen.Json.Decode.call_.decodeString errorDecoder
                                            (Elm.apply bodyToString [ body ])
                                        )
                                        { ok =
                                            ( "res"
                                            , \x ->
                                                Gen.Result.make_.err
                                                    (error.make_.knownBadStatus (Elm.get "statusCode" metadata) x)
                                            )
                                        , err =
                                            ( "_"
                                            , \_ ->
                                                Gen.Result.make_.err
                                                    (error.make_.badErrorBody metadata body)
                                            )
                                        }
                                )
                            }
                , goodStatus_ = \metadata body -> Elm.apply onSuccess [ metadata, body ]
                }
                |> Elm.withType
                    (Elm.Annotation.result
                        (error.annotation (Elm.Annotation.var "err") (Elm.Annotation.var "body"))
                        (Elm.Annotation.var "value")
                    )
        )


type alias CommonSubmodule =
    { decodeOptionalField : Elm.Expression -> Elm.Expression -> Elm.Expression
    , jsonDecodeAndMap : Elm.Expression -> Elm.Expression -> Elm.Expression
    , error :
        { annotation : Elm.Annotation.Annotation
        , case_ : Elm.Expression -> Error -> Elm.Expression
        , make_ : Error
        }
    , nullable :
        { annotation : Elm.Annotation.Annotation
        , case_ : Elm.Expression -> Nullable -> Elm.Expression
        , make_ : Nullable
        }
    }


commonSubmodule : Elm.Declare.Module CommonSubmodule
commonSubmodule =
    Elm.Declare.module_ Common.commonModuleName CommonSubmodule
        |> Elm.Declare.with decodeOptionalField
        |> Elm.Declare.with jsonDecodeAndMap
        |> Elm.Declare.with error
        |> Elm.Declare.with nullable


{-| Decode an optional field

    decodeString (decodeOptionalField "x" int) "{ \"x\": 3 }"
    --> Ok (Just 3)

    decodeString (decodeOptionalField "x" int) "{ \"x\": true }"
    --> Err ...

    decodeString (decodeOptionalField "x" int) "{ \"y\": 4 }"
    --> Ok Nothing

-}
decodeOptionalField : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
decodeOptionalField =
    let
        decoderAnnotation : Elm.Annotation.Annotation
        decoderAnnotation =
            Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "t")

        resultAnnotation : Elm.Annotation.Annotation
        resultAnnotation =
            Gen.Json.Decode.annotation_.decoder (Gen.Maybe.annotation_.maybe <| Elm.Annotation.var "t")

        body : Elm.Expression -> Elm.Expression -> Elm.Expression
        body key fieldDecoder =
            -- The tricky part is that we want to make sure that
            -- if the field exists we error out if it has an incorrect shape.
            -- So what we do is we `oneOf` with `value` to avoid the `Nothing` branch,
            -- `andThen` we decode it. This is why we can't just use `maybe`, we would
            -- give `Nothing` when the shape is wrong.
            Gen.Json.Decode.oneOf
                [ Gen.Json.Decode.call_.map
                    (Elm.fn Elm.Arg.ignore <| \_ -> Elm.bool True)
                    (Gen.Json.Decode.call_.field key Gen.Json.Decode.value)
                , Gen.Json.Decode.succeed (Elm.bool False)
                ]
                |> Gen.Json.Decode.andThen
                    (\hasField ->
                        Elm.ifThen hasField
                            (Gen.Json.Decode.call_.field key
                                (Gen.Json.Decode.oneOf
                                    [ Gen.Json.Decode.map Gen.Maybe.make_.just fieldDecoder
                                    , Gen.Json.Decode.null Gen.Maybe.make_.nothing
                                    ]
                                )
                            )
                            (Gen.Json.Decode.succeed Gen.Maybe.make_.nothing)
                    )
                |> Elm.withType resultAnnotation
    in
    Elm.Declare.fn2 "decodeOptionalField"
        (Elm.Arg.varWith "key" Elm.Annotation.string)
        (Elm.Arg.varWith "fieldDecoder" decoderAnnotation)
        body
        |> Elm.Declare.Extra.withDocumentation decodeOptionalFieldDocumentation


decodeOptionalFieldDocumentation : String
decodeOptionalFieldDocumentation =
    """Decode an optional field

    decodeString (decodeOptionalField "x" int) "{ "x": 3 }"
    --> Ok (Just 3)

    decodeString (decodeOptionalField "x" int) "{ "x": true }"
    --> Err ...

    decodeString (decodeOptionalField "x" int) "{ "y": 4 }"
    --> Ok Nothing"""


jsonDecodeAndMap : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
jsonDecodeAndMap =
    let
        aVarAnnotation : Elm.Annotation.Annotation
        aVarAnnotation =
            Elm.Annotation.var "a"

        aToBAnnotation : Elm.Annotation.Annotation
        aToBAnnotation =
            Elm.Annotation.function [ Elm.Annotation.var "a" ] (Elm.Annotation.var "b")

        bVarAnnotation : Elm.Annotation.Annotation
        bVarAnnotation =
            Elm.Annotation.var "b"
    in
    Elm.Declare.fn2 "jsonDecodeAndMap"
        (Elm.Arg.varWith "dx" (Gen.Json.Decode.annotation_.decoder aVarAnnotation))
        (Elm.Arg.varWith "df" (Gen.Json.Decode.annotation_.decoder aToBAnnotation))
        (\dx df ->
            Gen.Json.Decode.call_.map2 (Elm.val "(|>)") dx df
                |> Elm.withType (Gen.Json.Decode.annotation_.decoder bVarAnnotation)
        )
        |> Elm.Declare.Extra.withDocumentation "Chain JSON decoders, when `Json.Decode.map8` isn't enough."


type alias Error =
    { badUrl : Elm.Expression -> Elm.Expression
    , timeout : Elm.Expression
    , networkError : Elm.Expression
    , knownBadStatus : Elm.Expression -> Elm.Expression -> Elm.Expression
    , unknownBadStatus : Elm.Expression -> Elm.Expression -> Elm.Expression
    , badErrorBody : Elm.Expression -> Elm.Expression -> Elm.Expression
    , badBody : Elm.Expression -> Elm.Expression -> Elm.Expression
    }


error :
    { declaration : Elm.Declaration
    , annotation : Elm.Annotation.Annotation -> Elm.Annotation.Annotation -> Elm.Annotation.Annotation
    , make_ : Error
    , case_ : Elm.Expression -> Error -> Elm.Expression
    , internal :
        Elm.Declare.Internal
            { annotation : Elm.Annotation.Annotation
            , make_ : Error
            , case_ : Elm.Expression -> Error -> Elm.Expression
            }
    }
error =
    let
        base : Elm.Declare.CustomType Error
        base =
            Elm.Declare.customTypeAdvanced "Error" { exposeConstructor = True } Error
                |> Elm.Declare.variant1 "BadUrl" .badUrl Elm.Annotation.string
                |> Elm.Declare.variant0 "Timeout" .timeout
                |> Elm.Declare.variant0 "NetworkError" .networkError
                |> Elm.Declare.variant2 "KnownBadStatus" .knownBadStatus Elm.Annotation.int (Elm.Annotation.var "err")
                |> Elm.Declare.variant2 "UnknownBadStatus" .unknownBadStatus Gen.Http.annotation_.metadata (Elm.Annotation.var "body")
                |> Elm.Declare.variant2 "BadErrorBody" .badErrorBody Gen.Http.annotation_.metadata (Elm.Annotation.var "body")
                |> Elm.Declare.variant2 "BadBody" .badBody Gen.Http.annotation_.metadata (Elm.Annotation.var "body")
                |> Elm.Declare.finishCustomType
    in
    { declaration = base.declaration
    , annotation = \err ok -> Elm.Annotation.namedWith [] "Error" [ err, ok ]
    , make_ = base.make_
    , case_ = base.case_
    , internal = base.internal
    }


type alias Nullable =
    { null : Elm.Expression
    , present : Elm.Expression -> Elm.Expression
    }


nullable : Elm.Declare.CustomType Nullable
nullable =
    Elm.Declare.customTypeAdvanced "Nullable" { exposeConstructor = True } Nullable
        |> Elm.Declare.variant0 "Null" .null
        |> Elm.Declare.variant1 "Present" .present (Elm.Annotation.var "value")
        |> Elm.Declare.finishCustomType


outerJsonResolverCustom :
    String
    -> (Elm.Expression -> Elm.Expression -> Elm.Expression)
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
outerJsonResolverCustom name f =
    Elm.Declare.fn2 name
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "successDecoder"
            (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "success"))
        )
        f


outerRawResolverCustom :
    String
    -> (Elm.Expression -> Elm.Expression)
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression)
outerRawResolverCustom name f =
    Elm.Declare.fn name
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        f


outerExpectJsonCustom :
    String
    -> (Elm.Expression -> Elm.Expression -> (Elm.Expression -> Elm.Expression) -> Elm.Expression)
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
outerExpectJsonCustom name f =
    Elm.Declare.fn3 name
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "successDecoder"
            (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "success"))
        )
        (Elm.Arg.varWith "toMsg"
            (Elm.Annotation.function
                [ Elm.Annotation.result
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ errorAnnotation Elm.Annotation.string ]
                    )
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ Elm.Annotation.var "success" ]
                    )
                ]
                (Elm.Annotation.var "msg")
            )
        )
        (\errorDecoders successDecoders toMsg ->
            f errorDecoders
                successDecoders
                (\payload -> Elm.apply toMsg [ payload ])
        )


outerExpectStringCustom :
    Elm.Annotation.Annotation
    -> String
    -> (Elm.Expression -> (Elm.Expression -> Elm.Expression) -> Elm.Expression)
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
outerExpectStringCustom resultType name f =
    Elm.Declare.fn2 name
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "toMsg"
            (Elm.Annotation.function
                [ Elm.Annotation.result
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ errorAnnotation Elm.Annotation.string ]
                    )
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ resultType ]
                    )
                ]
                (Elm.Annotation.var "msg")
            )
        )
        (\errorDecoders toMsg ->
            f errorDecoders
                (\payload -> Elm.apply toMsg [ payload ])
        )


outerExpectBytesCustom :
    String
    -> (Elm.Expression -> (Elm.Expression -> Elm.Expression) -> Elm.Expression)
    -> Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
outerExpectBytesCustom name f =
    Elm.Declare.fn2 name
        (Elm.Arg.varWith "errorDecoders"
            (Gen.Dict.annotation_.dict
                Gen.String.annotation_.string
                (Gen.Json.Decode.annotation_.decoder (Elm.Annotation.var "err"))
            )
        )
        (Elm.Arg.varWith "toMsg"
            (Elm.Annotation.function
                [ Elm.Annotation.result
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ errorAnnotation Gen.Bytes.annotation_.bytes ]
                    )
                    (Elm.Annotation.namedWith Common.commonModuleName
                        "ResponseWithVersion"
                        [ Gen.Bytes.annotation_.bytes ]
                    )
                ]
                (Elm.Annotation.var "msg")
            )
        )
        (\errorDecoders toMsg ->
            f errorDecoders
                (\payload -> Elm.apply toMsg [ payload ])
        )


innerExpectJsonCustom :
    Elm.Expression
    -> Elm.Expression
    -> Elm.Expression
    -> Elm.Expression
innerExpectJsonCustom successDecoder metadata body =
    Elm.Case.result
        (Gen.Json.Decode.call_.decodeString successDecoder body)
        { err =
            ( "_"
            , \_ ->
                Gen.Result.make_.err (error.make_.badBody metadata body)
            )
        , ok = ( "res", Gen.Result.make_.ok )
        }


bytesToString : Elm.Expression -> Elm.Expression
bytesToString bytes =
    Gen.Bytes.Decode.decode (Gen.Bytes.Decode.call_.string (Gen.Bytes.width bytes)) bytes
        |> Gen.Maybe.withDefault (Elm.string "")
