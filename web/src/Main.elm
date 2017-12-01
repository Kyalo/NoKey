module Main exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onInput, onSubmit, onClick)
import Json.Encode as JE


-- TODO: change random to a higher bit version
-- also adapt the UUID package
-- see:
--  https://github.com/danyx23/elm-uuid/issues/10
--  https://github.com/mgold/elm-random-pcg/issues/18

import Random.Pcg as Random exposing (Generator, Seed)
import Uuid


-- https://github.com/saschatimme/elm-phoenix

import Phoenix
import Phoenix.Socket as Socket
import Phoenix.Channel as Channel
import Phoenix.Push as Push


--

import PasswordGenerator exposing (PasswordRequirements)
import PasswordGenerator.View as PW


type alias Model =
    { sites : List PasswordPart
    , newSiteEntry : PasswordMetaData
    , expandSiteEntry : Bool
    , requirementsState : PW.State
    , seed : Random.Seed
    , devices : List Device
    , messages : List JE.Value
    , input : String
    , uniqueIdentifyier : String
    }


type alias PasswordMetaData =
    { securityLevel : Int
    , length : Int
    , siteName : String
    , userName : String
    }


type alias Device =
    { name : String
    , status : DeviceStatus
    }


type DeviceStatus
    = Online
    | Offline
      -- local means the device that is actually running the code
    | Local


defaultMetaData : PasswordMetaData
defaultMetaData =
    { securityLevel = 2, length = 16, siteName = "", userName = "" }


resetMeta : PasswordMetaData -> PasswordMetaData
resetMeta meta =
    { meta | siteName = "" }


type alias PasswordPart =
    { pw : Random.Seed, meta : PasswordMetaData, requirements : PasswordRequirements }


splitPassword : PasswordMetaData -> PW.State -> Random.Seed -> PasswordPart
splitPassword meta req seed =
    -- TODO: the seed is the actual password!
    -- since the seed IS the password, it should have at least as many bytes of randomness as the desired password length!
    -- Use the seed that was used to generate the password and split it into parts.
    -- Use Shamir's secret sharing algorithm
    PasswordPart (seed) meta (PW.getRequirements req)


socketUrl : String
socketUrl =
    -- TODO: change
    "localhost"
        -- "10.2.117.8"
        |> (\ip -> "ws://" ++ ip ++ ":4000/socket/websocket")


randomUUID : Generator String
randomUUID =
    Random.map Uuid.toString Uuid.uuidGenerator


initModel : Int -> Model
initModel randInt =
    let
        ( uuid, seed2 ) =
            Random.step randomUUID (Random.initialSeed randInt)
    in
        { sites = []
        , newSiteEntry = defaultMetaData
        , expandSiteEntry = False
        , requirementsState = PW.init
        , seed = seed2
        , uniqueIdentifyier = uuid
        , devices = [ { name = "Local PC", status = Local } ]
        , messages = []
        , input = ""
        }


type alias Flags =
    { initialSeed : Int }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( initModel flags.initialSeed, Cmd.none )


type Msg
    = AddPassword
    | SiteNameChanged String
    | PasswordLengthChanged Int
    | SecurityLevelChanged Int
    | NewPasswordRequirements PW.State
    | GenerateNewPassword
    | UserNameChanged String
    | ReceiveMessage JE.Value
    | SendMessage JE.Value
    | SetInput String


noCmd : a -> ( a, Cmd msg )
noCmd a =
    ( a, Cmd.none )


withCmd : Cmd msg -> a -> ( a, Cmd msg )
withCmd cmd a =
    ( a, cmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AddPassword ->
            let
                pwPart =
                    splitPassword model.newSiteEntry model.requirementsState model.seed
            in
                { model | sites = pwPart :: model.sites, newSiteEntry = resetMeta model.newSiteEntry, expandSiteEntry = False }
                    |> updateSeed
                    |> noCmd

        SiteNameChanged s ->
            { model | newSiteEntry = (\e -> { e | siteName = s }) model.newSiteEntry, expandSiteEntry = not <| String.isEmpty s }
                |> noCmd

        SecurityLevelChanged n ->
            { model | newSiteEntry = (\e -> { e | securityLevel = n }) model.newSiteEntry }
                |> noCmd

        GenerateNewPassword ->
            updateSeed model
                |> noCmd

        NewPasswordRequirements state ->
            { model | requirementsState = state }
                |> updateSeed
                |> noCmd

        PasswordLengthChanged l ->
            { model | newSiteEntry = (\e -> { e | length = l }) model.newSiteEntry }
                |> updateSeed
                |> noCmd

        UserNameChanged n ->
            { model | newSiteEntry = (\e -> { e | userName = n }) model.newSiteEntry }
                |> noCmd

        ReceiveMessage msg ->
            ( { model | messages = msg :: model.messages }
            , Cmd.none
            )

        SendMessage msg ->
            let
                push =
                    Push.init "private:lobby" "new_msg"
                        |> Push.withPayload msg
            in
                ( { model | input = "" }
                , Phoenix.push socketUrl push
                )

        SetInput i ->
            { model | input = i } |> noCmd


updateSeed : Model -> Model
updateSeed model =
    { model
        | seed =
            Tuple.second <| PW.getNextPassword model.requirementsState model.newSiteEntry.length model.seed
    }


view : Model -> Html Msg
view model =
    Html.div []
        [ viewDevices model.devices
        , addNewDevice
        , newSiteForm model.requirementsState model.expandSiteEntry model.newSiteEntry model.seed
        , viewSavedSites model.sites
        , Html.div []
            [ Html.form [ onSubmit (SendMessage (JE.object [ ( "body", JE.string model.input ) ])) ]
                [ Html.input [ Attr.value model.input, onInput SetInput ] []
                ]
            ]
        , Html.div [] [ Html.text (toString model.messages) ]
        ]


addNewDevice : Html Msg
addNewDevice =
    -- TODO: display QR code
    -- probably using: pablohirafuji/elm-qrcode
    Html.button [] [ Html.text "Add new device" ]


viewDevices : List Device -> Html Msg
viewDevices devs =
    Html.table []
        (Html.tr [] [ Html.th [] [ Html.text "name" ], Html.th [] [ Html.text "status" ] ]
            :: List.map viewDeviceEntry devs
        )


viewDeviceEntry : Device -> Html Msg
viewDeviceEntry dev =
    Html.tr []
        [ Html.td [] [ Html.text dev.name ]
        , Html.td [] [ Html.text (toString dev.status) ]
        ]


viewSavedSites : List PasswordPart -> Html Msg
viewSavedSites sites =
    Html.div []
        (List.map
            (\({ meta } as spw) ->
                Html.div [] [ Html.h3 [] [ Html.text meta.siteName ], Html.text (toString spw) ]
            )
            sites
        )


clampedNumberInput : (Int -> msg) -> ( Int, Int, Int ) -> Int -> Html msg
clampedNumberInput toMsg ( min, default, max ) n =
    let
        m =
            clamp min max n
    in
        Html.input
            [ Attr.type_ "number"
            , Attr.min (toString min)
            , Attr.max (toString max)
            , Attr.value (toString m)
            , onInput (\s -> String.toInt s |> Result.map (clamp min max) |> Result.withDefault default |> toMsg)
            ]
            []


newSiteForm : PW.State -> Bool -> PasswordMetaData -> Seed -> Html Msg
newSiteForm requirementsState expandSiteEntry entry seed =
    let
        pw =
            Tuple.first (PW.getNextPassword requirementsState entry.length seed)
    in
        Html.div []
            [ Html.form [ onSubmit GenerateNewPassword ]
                [ Html.text "New Site: "
                , Html.input [ Attr.placeholder "example.com", Attr.value entry.siteName, onInput SiteNameChanged ] []
                ]
            , (if not expandSiteEntry then
                Html.text ""
               else
                Html.div []
                    ([ Html.text "Login name: "
                     , Html.input [ Attr.value entry.userName, onInput UserNameChanged ] []
                     , Html.text "Security Level: "

                     -- TODO: limit max by number of available devices.
                     , clampedNumberInput SecurityLevelChanged ( 2, 2, 5 ) entry.securityLevel
                     , Html.text "Password length: "
                     , clampedNumberInput PasswordLengthChanged ( 4, 16, 512 ) entry.length
                     , PW.view NewPasswordRequirements requirementsState
                     ]
                        ++ case pw of
                            Ok thePw ->
                                [ Html.text "your new password: "
                                , Html.text thePw
                                , Html.div
                                    []
                                    [ Html.button [ onClick AddPassword ] [ Html.text "OK" ]
                                    , Html.button [ onClick GenerateNewPassword ] [ Html.text "Generate another one!" ]
                                    ]
                                ]

                            Err e ->
                                [ Html.text e ]
                    )
              )
            ]


subs : Model -> Sub Msg
subs model =
    let
        socket =
            Socket.init socketUrl

        channel =
            Channel.init "private:lobby"
                -- register a handler for messages with a "new_msg" event
                |> Channel.on "new_msg" ReceiveMessage
                |> Channel.withDebug
                |> Channel.withPayload (JE.object [ ( "uuid", JE.string model.uniqueIdentifyier ) ])
    in
        Phoenix.connect socket [ channel ]


main : Program Flags Model Msg
main =
    Html.programWithFlags
        { init = init
        , subscriptions = subs
        , view = view
        , update = update
        }
