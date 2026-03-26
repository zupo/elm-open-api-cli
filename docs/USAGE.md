# Using the CLI

### Install the CLI:

-   `npm install -D elm-open-api`

### Run the CLI:

-   `npx elm-open-api ./page/to/oas.json`

### Arguments you can pass:

-   `<entryFilePath>`: The path to the Open API Spec, either `.json` or `.y[a]ml`
    -   Technically the OAS allows for parts of a spec to be in separate files, but this isn't supported yet.
-   `[--output-dir <output dir>]`: The directory to output to. Defaults to `generated/`.
-   `[--module-name <module name>]`: The Elm module name. Default to `<OAS info.title>`.
-   `[--response-version-header <header name>]`: Expose a response version header through `OpenApi.Common.responseVersionFromError`.
    -   Pass the exact response header name you want to expose.
    -   This lets your app forward the server's response version to JavaScript or a port.
    -   Comparison, storage, and reload behavior stay in your application code.
-   `[--auto-convert-swagger]`: If passed in, and a Swagger doc is encountered, will attempt to convert it to an Open API file. If not passed in, and a Swagger doc is encountered, the user will be manually prompted to convert.
-   `[--swagger-conversion-url]`: The URL to use to convert a Swagger doc to an Open API file. Defaults to `https://converter.swagger.io/api/convert`.
-   `[--swagger-conversion-command]`: Instead of making an HTTP request to convert from Swagger to Open API, use this command.
-   `[--swagger-conversion-command-args]`: Additional arguments to pass to the Swagger conversion command, before the contents of the Swagger file are passed in.
-   `[--generateTodos <generateTodos>]`: Whether to generate TODOs for unimplemented endpoints, or fail when something unexpected is encountered. Defaults to `no`. To generate `Debug.todo ""` instead of failing use one of: `yes`, `y`, `true`.
-   `[--overrides <file path>]`: Load an additional file to override parts of the original Open API file.
    - This is most commonly used for malformed OAS files (e.g. missing `required` on a required field) but can be used for anything you want
-   `[--write-merged-to <file path>]`: Write the merged Open API spec to the given file (see `--overrides` for merging).

## Working with response versions

If your backend includes a response header like `OpenAPI-Hash`, you can ask the generator to expose that header through generated `OpenApi.Common` helpers:

```sh
npx elm-open-api ./my-cool-company-oas.json --response-version-header OpenAPI-Hash
```

When enabled, the generated `OpenApi.Common` module includes:

-   `type alias ResponseVersion = { headerName : String, responseVersion : String }`
-   `responseVersionFromError : Error err body -> Maybe ResponseVersion`

This helper extracts the configured response version header from generated API errors that include response metadata, such as `BadBody`, `BadErrorBody`, and `UnknownBadStatus`.

Use this when you want your application to observe the response version itself, typically by forwarding the observed value to JavaScript, a port, or shared app state.

### Generic app setup

1. Enable the feature with `--response-version-header <header name>`.
2. Route generated API errors through one shared error handler.
3. In that shared handler, call `OpenApi.Common.responseVersionFromError`.
4. When it returns `Just responseVersion`, forward that value to JavaScript, a port, or shared app state.
5. Handle that forwarded value however your application needs.

Example shared handling:

```elm
case result of
    Err err ->
        case OpenApi.Common.responseVersionFromError err of
            Just responseVersion ->
                forwardObservedResponseVersion err responseVersion

            Nothing ->
                handleNormalApiError err

    Ok value ->
        handleSuccess value
```

Notes:

-   This only exposes response versions from generated API errors that include response metadata.
-   If you need to inspect the header on every successful response too, use a JavaScript interceptor instead.
-   The generated SDK only exposes the observed response version. Any follow-up behavior is app-owned.
-   For cross-origin APIs, your backend must expose the response version header through CORS.

### Elm Land

Elm Land is a good fit for this feature when you already use a customized `Effect.elm` and `src/interop.js` for JavaScript interop.

Use this flow when:

-   you want one shared application-level place to observe response versions from generated API errors
-   you want JavaScript or ports to receive that observed value
-   you do not want to thread extra config through every generated API call

#### 1. Enable the generator flag

```sh
npx elm-open-api ./my-cool-company-oas.json --response-version-header OpenAPI-Hash
```

#### 2. Customize `Effect.elm`

If you have not already customized it:

```sh
elm-land customize effect
```

Then add an effect that forwards the observed response version to JavaScript.

Example `src/Effect.elm`:

```elm
port module Effect exposing
    ( Effect
    , none
    , map
    , toCmd
    , reportResponseVersion
    )

import Json.Encode

type Effect msg
    = None
    | SendMessageToJavaScript
        { tag : String
        , data : Json.Encode.Value
        }

port outgoing : { tag : String, data : Json.Encode.Value } -> Cmd msg

none : Effect msg
none =
    None

reportResponseVersion :
    { headerName : String, responseVersion : String }
    -> Effect msg
reportResponseVersion payload =
    SendMessageToJavaScript
        { tag = "REPORT_RESPONSE_VERSION"
        , data =
            Json.Encode.object
                [ ( "headerName", Json.Encode.string payload.headerName )
                , ( "responseVersion", Json.Encode.string payload.responseVersion )
                ]
        }

map : (msg1 -> msg2) -> Effect msg1 -> Effect msg2
map _ effect =
    case effect of
        None ->
            None

        SendMessageToJavaScript message ->
            SendMessageToJavaScript message

toCmd : Effect msg -> Cmd msg
toCmd effect =
    case effect of
        None ->
            Cmd.none

        SendMessageToJavaScript message ->
            outgoing message
```

#### 3. Handle generated API errors in one shared place

Use `OpenApi.Common.responseVersionFromError` inside your shared request result handler:

```elm
case result of
    Err err ->
        case OpenApi.Common.responseVersionFromError err of
            Just responseVersion ->
                ( model
                , Effect.reportResponseVersion
                    { headerName = responseVersion.headerName
                    , responseVersion = responseVersion.responseVersion
                    }
                )

            Nothing ->
                handleNormalApiError model err

    Ok value ->
        handleSuccess model value
```

This becomes app-global when all generated API errors are funneled through one shared handler. It is not an implicit interceptor.

#### 4. Receive the forwarded version in `src/interop.js`

The generator stops at `OpenApi.Common.responseVersionFromError`. The app decides what, if anything, should happen next.

Example `src/interop.js`:

```js
export const onReady = ({ app }) => {
  if (!app.ports || !app.ports.outgoing) return

  app.ports.outgoing.subscribe(({ tag, data }) => {
    if (tag !== 'REPORT_RESPONSE_VERSION') return

    handleObservedResponseVersion(data)
  })
}
```

Here `handleObservedResponseVersion` is application code. It might store the value, compare it, log it, or ignore it. That behavior is not generated by `elm-open-api`.

#### 5. Important caveats

-   This flow reacts to generated API errors with response metadata, not every successful response.
-   If your users frequently keep tabs open for a long time and you need detection on every response, prefer a JavaScript interceptor.
-   For cross-origin APIs, make sure the response version header is exposed to the browser via CORS.
## Example outputs:

Assume we have an OAS file named `my-cool-company-oas.json` and it has a field `"title": "My Coool Company"` and we run the CLI like so

```sh
npx elm-open-api ./my-cool-company-oas.json
```

then we'll output like

```sh
🎉 SDK generated:

    generated/MyCooolCompany/Api.elm
    generated/MyCooolCompany/Json.elm
    generated/MyCooolCompany/Types.elm
    generated/OpenApi/Common.elm


You'll also need elm/http and elm/json installed. Try running:

    elm install elm/http
    elm install elm/json


and possibly need elm/bytes and elm/url installed. If that's the case, try running:
    elm install elm/bytes
    elm install elm/url
```

That's nice, but maybe we want to have a less specific module name. We could instead run

```sh
npx elm-open-api ./my-cool-company-oas.json --module-name="My.Comp"
```

which would result in

```sh
🎉 SDK generated:

    generated/My/Comp/Api.elm
    generated/My/Comp/Json.elm
    generated/My/Comp/Types.elm
    generated/OpenApi/Common.elm


You'll also need elm/http and elm/json installed. Try running:

    elm install elm/http
    elm install elm/json


and possibly need elm/bytes and elm/url installed. If that's the case, try running:
    elm install elm/bytes
    elm install elm/url
```

Notice the new path (and Elm module name) for the files.

Alternatively, maybe we have a different directory naming scheme for our project. We could do

```sh
npx elm-open-api ./my-cool-company-oas.json --output-dir="src"
```

which gives us

```sh
🎉 SDK generated:

    src/MyCooolCompany/Api.elm
    src/MyCooolCompany/Json.elm
    src/MyCooolCompany/Types.elm
    src/OpenApi/Common.elm


You'll also need elm/http and elm/json installed. Try running:

    elm install elm/http
    elm install elm/json


and possibly need elm/bytes and elm/url installed. If that's the case, try running:
    elm install elm/bytes
    elm install elm/url
```

This time only the root directory has changed.
