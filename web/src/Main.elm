module Main exposing (..)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (onInput, onSubmit, onClick)
import Html.Lazy exposing (lazy, lazy2)
import Html.Keyed
import Json.Encode as JE exposing (Value)
import Json.Decode as JD exposing (Decoder)
import Dict exposing (Dict)
import Set exposing (Set)
import Time exposing (Time)
import Date
import Task


-- TODO:
-- adapt the UUID package to use pcg-extended
-- see:
--  https://github.com/danyx23/elm-uuid/issues/10

import Random.Pcg.Extended as RandomE
import Random.Pcg as Random exposing (Generator, Seed)
import Http
import Uuid
import RemoteData exposing (WebData)
import Debounce exposing (Debounce)


--

import PasswordGenerator exposing (PasswordRequirements)
import PasswordGenerator.View as PW
import Pairing
import SyncData exposing (SyncData)
import Api
import Helper exposing (boolToInt, maybeToList, noCmd, withCmds, addCmds)
import SecretSharing
import Crdt.ORDict as ORDict exposing (ORDict)
import Ports


type alias Model =
    { newSiteEntry : PasswordMetaData
    , expandSiteEntry : Bool
    , requirementsState : PW.State
    , pairingDialogue : Pairing.State
    , showPairingDialogue : Bool
    , seed : RandomE.Seed
    , onlineDevices : Devices
    , sitesState : SiteState
    , debounce : Debounce ()
    , shareRequests : List ShareRequest

    -- TODO: The ones below should be serialized:
    , uniqueIdentifyier : String

    -- CRDT for synchronisation
    , syncData : SyncData
    }


type alias SaveState =
    { syncData : SyncData, uuid : String }


stateDecoder : Decoder SaveState
stateDecoder =
    JD.map2 SaveState
        (JD.field "syncData" SyncData.completeDecoder)
        (JD.field "uuid" JD.string)


encodeState : Model -> Value
encodeState { syncData, uniqueIdentifyier } =
    JE.object
        [ ( "syncData", SyncData.encodeComplete syncData )
        , ( "uuid", JE.string uniqueIdentifyier )
        ]


type alias ShareRequest =
    { id : String
    , key : ( String, String )
    }


type alias SiteState =
    Dict ( String, String ) (List SecretSharing.Share)


type alias PasswordMetaData =
    { securityLevel : Int
    , length : Int
    , siteName : String
    , userName : String
    }


type alias Devices =
    Set String


devicesMap : (String -> String -> DeviceStatus -> b) -> ORDict String ( Int, String ) -> Devices -> List b
devicesMap f known_ids devs =
    Dict.foldl
        (\uuid ( _, name ) acc ->
            if Set.member uuid devs then
                f uuid name Online :: acc
            else
                f uuid name Offline :: acc
        )
        []
        (ORDict.get known_ids)


type DeviceStatus
    = Online
    | Offline


defaultMetaData : PasswordMetaData
defaultMetaData =
    { securityLevel = 2, length = 16, siteName = "", userName = "" }


resetMeta : PasswordMetaData -> PasswordMetaData
resetMeta meta =
    { meta | siteName = "" }


type alias PasswordPart =
    { pw : Random.Seed, meta : PasswordMetaData, requirements : PasswordRequirements }


randomUUID : Generator String
randomUUID =
    Random.map Uuid.toString Uuid.uuidGenerator


initModel : Flags -> Model
initModel { initialSeed, storedState } =
    let
        ( base, ext ) =
            initialSeed

        ( uuid, seed2 ) =
            -- TODO: replace with pcg-extended
            Random.step randomUUID (Random.initialSeed base)

        ( indepSeed, seed3 ) =
            Random.step Random.independentSeed seed2

        makeInit mayId maySync =
            { newSiteEntry = defaultMetaData
            , expandSiteEntry = False
            , requirementsState = PW.init
            , seed = RandomE.initialSeed base ext
            , debounce = Debounce.init
            , uniqueIdentifyier = Maybe.withDefault uuid mayId
            , syncData = Maybe.withDefault (SyncData.init indepSeed uuid) maySync
            , onlineDevices = Set.empty
            , pairingDialogue = Pairing.init
            , showPairingDialogue = True
            , shareRequests = []
            , sitesState = Dict.empty
            }
    in
        case JD.decodeValue stateDecoder storedState of
            Ok { syncData, uuid } ->
                makeInit (Just uuid) (Just syncData)

            Err err ->
                let
                    _ =
                        Debug.log "couldn't decode state" err
                in
                    makeInit Nothing Nothing


debounceConfig : Debounce.Config Msg
debounceConfig =
    { strategy = Debounce.soon (1 * Time.second)
    , transform = SyncToOthers
    }


type alias Flags =
    { initialSeed : ( Int, List Int )
    , storedState : Value
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        newModel =
            initModel flags
    in
        newModel |> withCmds [ storeState newModel ]


storeState : Model -> Cmd Msg
storeState model =
    Ports.storeState (encodeState model)


type Msg
    = AddPassword String
    | SiteNameChanged String
    | PasswordLengthChanged Int
    | SecurityLevelChanged Int
    | NewPasswordRequirements PW.State
    | GenerateNewPassword
    | UserNameChanged String
    | ReceiveMessage JE.Value
    | DecodeReceivedMessage JE.Value Time
    | ReceiveToken (WebData String)
    | PairDeviceClicked
    | GetTokenClicked
    | UpdatePairing Pairing.State
    | TokenSubmitted
    | PairedWith (Result Http.Error ( String, SyncData, Time ))
    | RejoinChannel JE.Value
    | RemoveDevice String
    | SetDeviceName String
    | SyncToOthers Debounce.Msg
    | InsertSite String String (Dict String SecretSharing.Share) Int Time
    | RequestPasswordPressed ( String, String )
    | GrantShareRequest ShareRequest
    | RejectShareRequest ShareRequest
    | NoOp


withTimestamp : (Time -> msg) -> Cmd msg
withTimestamp toMsg =
    Time.now
        |> Task.perform (toMsg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            model |> noCmd

        AddPassword pw ->
            let
                ( shares, seed2 ) =
                    SecretSharing.splitString
                        ( model.newSiteEntry.securityLevel
                        , SyncData.knownIds model.syncData |> List.length
                        )
                        pw
                        model.seed

                share =
                    List.map2
                        (\id share ->
                            ( id, share )
                        )
                        (SyncData.knownIds model.syncData)
                        shares
                        |> Dict.fromList

                { userName, siteName } =
                    model.newSiteEntry
            in
                { model
                    | newSiteEntry = resetMeta model.newSiteEntry
                    , expandSiteEntry = False
                    , seed = seed2
                }
                    |> updateSeed
                    |> withCmds [ withTimestamp (InsertSite siteName userName share model.newSiteEntry.securityLevel) ]

        InsertSite siteName userName share requiredParts timestamp ->
            { model | syncData = SyncData.insertSite timestamp requiredParts siteName userName share model.syncData }
                |> syncToOthers

        SiteNameChanged s ->
            { model
                | newSiteEntry = (\e -> { e | siteName = s }) model.newSiteEntry
                , expandSiteEntry = not <| String.isEmpty s
            }
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
            model |> withCmds [ withTimestamp (DecodeReceivedMessage msg) ]

        DecodeReceivedMessage msg timestamp ->
            -- TODO: Include authenticity to messages and reject not authentic messages
            case JD.decodeValue Api.serverResponseDecoder msg of
                Ok ( id, apiMsg ) ->
                    let
                        _ =
                            Debug.log ("at:   " ++ toString (Date.fromTime timestamp) ++ "\nfrom: " ++ id ++ "\n\n")
                                apiMsg
                    in
                        case apiMsg of
                            Api.PairedWith syncData ->
                                -- TODO: only accept a PairedWith message if we are expecting one.
                                -- Otherwise anyone could pair with us, as long as they know our id
                                { model | pairingDialogue = Pairing.pairingCompleted (Ok id) model.pairingDialogue }
                                    |> pairedWith timestamp id syncData

                            other ->
                                if SyncData.isKnownId id model.syncData then
                                    case other of
                                        Api.SyncUpdate syncData ->
                                            syncUpdate timestamp syncData model

                                        Api.GotRemoved ->
                                            { model | syncData = SyncData.gotRemoved model.syncData } |> noCmd

                                        Api.RequestShare key ->
                                            { model | shareRequests = { id = id, key = key } :: model.shareRequests }
                                                |> noCmd

                                        Api.GrantedShareRequest key share ->
                                            { model
                                                | sitesState =
                                                    Dict.update key
                                                        (Maybe.map (\a -> share :: a))
                                                        model.sitesState
                                            }
                                                |> noCmd

                                        Api.PairedWith _ ->
                                            -- TODO: refactor, split Api messages into Authenticated / Anonymous messages
                                            Debug.crash "This can't happen, the branch is already covered by the surrounding case statement"
                                else
                                    model |> noCmd

                Err e ->
                    let
                        _ =
                            Debug.log "parse msg failed:" e
                    in
                        model |> noCmd

        ReceiveToken token ->
            ( { model | pairingDialogue = Pairing.receivedToken token model.pairingDialogue }, Cmd.none )

        PairDeviceClicked ->
            { model | showPairingDialogue = not model.showPairingDialogue }
                |> noCmd

        GetTokenClicked ->
            model
                |> (\m -> { m | pairingDialogue = Pairing.getTockenClicked model.pairingDialogue })
                |> withCmds [ Api.initPairing ReceiveToken model.uniqueIdentifyier model.syncData ]

        UpdatePairing s ->
            { model | pairingDialogue = s }
                |> noCmd

        TokenSubmitted ->
            model
                |> (\m -> { m | pairingDialogue = Pairing.tokenSubmitted m.pairingDialogue })
                |> withCmds [ Api.pairWith PairedWith model.uniqueIdentifyier model.pairingDialogue.inputToken model.syncData ]

        PairedWith res ->
            case res of
                Ok ( id, syncData, timestamp ) ->
                    model
                        |> (\m -> { m | pairingDialogue = Pairing.pairingCompleted (Ok id) m.pairingDialogue })
                        |> pairedWith timestamp id syncData

                Err e ->
                    model
                        |> (\m -> { m | pairingDialogue = Pairing.pairingCompleted (Err e) m.pairingDialogue })
                        |> noCmd

        RejoinChannel v ->
            let
                _ =
                    Debug.log "RejoinChannel" ()
            in
                model
                    |> syncToOthers

        RemoveDevice uuid ->
            let
                ( sync, removeCmd ) =
                    Api.removeDevice NoOp uuid model.syncData
            in
                { model | syncData = sync }
                    |> syncToOthers
                    |> addCmds [ removeCmd ]

        SetDeviceName newName ->
            let
                newSync =
                    -- do not sync immediately to reduce #of messages.
                    SyncData.renameDevice newName model.syncData
            in
                { model | syncData = newSync }
                    |> syncToOthers
                    |> addCmds [ Ports.setTitle ("NoPass (" ++ newName ++ ")") ]

        SyncToOthers msg ->
            -- delay the sync update to others, as we might get multiple updates in a short time, so wait until it settled.
            let
                ( newSync, cmdToDebounce ) =
                    Api.syncToOthers NoOp model.syncData

                ( debounce, cmd ) =
                    Debounce.update
                        debounceConfig
                        (Debounce.takeLast (always cmdToDebounce))
                        msg
                        model.debounce

                newModel =
                    { model | debounce = debounce, syncData = newSync }
            in
                newModel
                    |> withCmds [ cmd, storeState newModel ]

        RequestPasswordPressed key ->
            { model | sitesState = Dict.insert key [] model.sitesState }
                |> withCmds [ Api.requestShare NoOp key model.syncData ]

        GrantShareRequest req ->
            { model | shareRequests = List.filter (\it -> it /= req) model.shareRequests }
                |> withCmds [ Api.grantRequest NoOp req model.syncData ]

        RejectShareRequest req ->
            -- TODO: inform other of reject?
            { model | shareRequests = List.filter (\it -> it /= req) model.shareRequests }
                |> noCmd


pairedWith : Time -> String -> SyncData -> Model -> ( Model, Cmd Msg )
pairedWith timestamp id syncData model =
    { model | onlineDevices = Set.insert id model.onlineDevices }
        |> syncUpdate timestamp syncData


syncToOthers : Model -> ( Model, Cmd Msg )
syncToOthers model =
    let
        ( debounce, cmd ) =
            Debounce.push debounceConfig () model.debounce
    in
        ( { model | debounce = debounce }, cmd )


syncUpdate : Time -> SyncData -> Model -> ( Model, Cmd Msg )
syncUpdate timestamp syncData model =
    let
        newSync =
            SyncData.merge timestamp syncData model.syncData

        ( debounce, cmd ) =
            Debounce.push debounceConfig () model.debounce
    in
        ( { model | syncData = newSync, debounce = debounce }
        , cmd
        )


updateSeed : Model -> Model
updateSeed model =
    { model
        | seed =
            Tuple.second <| PW.getNextPassword model.requirementsState model.newSiteEntry.length model.seed
    }


view : Model -> Html Msg
view model =
    let
        numberOfKnownDevices =
            SyncData.knownIds model.syncData |> List.length
    in
        Html.div []
            [ viewDevices model.uniqueIdentifyier model.syncData.knownIds model.onlineDevices
            , Pairing.view (pairingConfig model.showPairingDialogue) model.pairingDialogue
            , Html.hr [] []
            , Html.div [] (List.map viewShareRequest model.shareRequests)
            , Html.hr [] []
            , if numberOfKnownDevices >= 2 then
                newSiteForm model.requirementsState model.expandSiteEntry model.newSiteEntry numberOfKnownDevices model.seed
              else
                Html.text "pair a device to save your first password"
            , Html.hr [] []
            , lazy2 viewSavedSites model.sitesState model.syncData
            ]


pairingConfig : Bool -> Pairing.Config Msg
pairingConfig doShow =
    { doShow = doShow, onSubmitToken = TokenSubmitted, onGetTokenClicked = GetTokenClicked, toMsg = UpdatePairing }


viewShareRequest : ShareRequest -> Html Msg
viewShareRequest req =
    Html.div []
        [ Html.div [] [ Html.b [] [ Html.text req.id ], Html.text (" wants to view password for: " ++ toString req.key) ]
        , Html.div []
            [ Html.button [ onClick (RejectShareRequest req) ] [ Html.text "Reject" ]
            , Html.button [ onClick (GrantShareRequest req) ] [ Html.text "Grant" ]
            ]
        ]


viewDevices : String -> ORDict String ( Int, String ) -> Devices -> Html Msg
viewDevices myId knownIds devs =
    Html.table []
        (Html.tr [] [ Html.th [] [ Html.text "name" ], Html.th [] [ Html.text "uuid" ] ]
            -- TODO. see if there is a reliable method for detecting online devices
            -- , Html.th [] [ Html.text "status" ] ]
            :: devicesMap (viewDeviceEntry myId) knownIds devs
        )


viewDeviceEntry : String -> String -> String -> DeviceStatus -> Html Msg
viewDeviceEntry myId uuid name status =
    Html.tr []
        ([ Html.td []
            [ if myId == uuid then
                Html.input [ Attr.value name, onInput SetDeviceName, Attr.placeholder "Name your device.." ] []
              else
                Html.text name
            ]
         , Html.td [] [ Html.text uuid ]

         -- , Html.td [] [ Html.text (toString status) ]
         ]
            ++ (if myId /= uuid then
                    [ Html.button [ onClick (RemoveDevice uuid) ] [ Html.text "Remove!" ] ]
                else
                    []
               )
        )


viewSavedSites : SiteState -> SyncData -> Html Msg
viewSavedSites sitesState sync =
    SyncData.mapSavedSites (viewSavedSite sitesState) sync
        |> Html.Keyed.node "div" []


viewSavedSite : SiteState -> String -> String -> Int -> Maybe SecretSharing.Share -> ( String, Html Msg )
viewSavedSite sitesState siteName userName requiredParts mayShare =
    Html.div []
        [ Html.div [] [ Html.b [] [ Html.text siteName ] ]
        , Html.div []
            [ Html.text userName
            , Html.text (" -> has share: " ++ toString (Nothing /= mayShare))
            , Html.div []
                [ case Dict.get ( siteName, userName ) sitesState of
                    Just recShares ->
                        let
                            shares =
                                maybeToList mayShare ++ recShares
                        in
                            if (List.length shares) >= requiredParts then
                                -- expensive operation
                                Html.text ("Password: " ++ toString (SecretSharing.joinToString shares))
                            else
                                Html.text <| "Received " ++ toString (List.length shares) ++ "/" ++ toString requiredParts ++ " shares"

                    Nothing ->
                        Html.button [ onClick (RequestPasswordPressed ( siteName, userName )) ] [ Html.text "Request password" ]
                ]
            ]
        ]
        |> (\html -> ( siteName ++ userName, html ))


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


newSiteForm : PW.State -> Bool -> PasswordMetaData -> Int -> RandomE.Seed -> Html Msg
newSiteForm requirementsState expandSiteEntry entry maxSecurityLevel seed =
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
                     , clampedNumberInput SecurityLevelChanged ( 2, 2, maxSecurityLevel ) entry.securityLevel
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
                                    [ Html.button [ onClick (AddPassword thePw) ] [ Html.text "OK" ]
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
    Api.connectPrivateSocket ReceiveMessage RejoinChannel model.uniqueIdentifyier


main : Program Flags Model Msg
main =
    Html.programWithFlags
        { init = init
        , subscriptions = subs
        , view = view
        , update = update
        }
