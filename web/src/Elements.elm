module Elements exposing (..)

import Html.Attributes as Attr
import Html.Events as Events
import Html
import Json.Decode as JD
import Element exposing (..)
import Element.Input as Input
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Styles
import HashIcon
import Icons
import Data exposing (..)
import Route exposing (Page(..))
import Helper


-- attributes


hackInLineStyle : String -> String -> Attribute msg
hackInLineStyle prop val =
    htmlAttribute (Attr.style [ ( prop, val ) ])


onEnter : msg -> Attribute msg
onEnter =
    onKey 13


onKey : Int -> msg -> Element.Attribute msg
onKey desiredCode msg =
    let
        decode code =
            if code == desiredCode then
                JD.succeed msg
            else
                JD.fail "Not the key"

        isKey =
            JD.field "which" JD.int
                |> JD.andThen decode
    in
        htmlAttribute <|
            Events.onWithOptions "keyup"
                { stopPropagation = False
                , preventDefault = True
                }
                isKey



-- Wrappers


inputGroup : String -> List (Element msg) -> Element msg
inputGroup heading contents =
    column [ paddingXY 0 (Styles.paddingScale 1), spacing (Styles.paddingScale 2), alignLeft ]
        (el Styles.groupHeading (h4 heading) :: contents)


container : List (Element msg) -> Element msg
container contents =
    column [ padding (Styles.paddingScale 2), spacing (Styles.paddingScale 1) ] contents


buttonRow : List (Attribute msg) -> List (Element msg) -> Element msg
buttonRow attrs btns =
    row (padding (Styles.paddingScale 3) :: attrs) (List.intersperse spacer btns)


card : Int -> List (Attribute msg) -> List (Element msg) -> Element msg
card depth attr children =
    column
        ([ -- Background.color Styles.white
           height shrink
         , Background.color Styles.altBackgroundColor
         , spacing (Styles.paddingScale 1)
         , padding (Styles.scaled 1)

         -- 1px 1px 3px 0px ;
         ]
            ++ attr
            ++ Styles.cardShadow depth
        )
        children



-- Element wrappers


wrapInBorder : Element msg -> Element msg
wrapInBorder ele =
    el
        [ Border.color Styles.thinLineColor
        , width fill
        , Border.widthEach { bottom = 2, left = 0, right = 0, top = 0 }
        , padding (Styles.paddingScale 1)
        ]
        ele


withLabel : String -> Element msg -> Element msg
withLabel label ele =
    row []
        [ el [ width (fillPortion 1) ] (text label)
        , el [ width (fillPortion 3) ] ele
        ]


{-| Take a list [a,b,c] and add commas and 'and's in between.

    enumeration text ["carrot", "apple", "tomato"] ->
        List.map text ["carrot", ",", "apple", "and", "tomato"]

-}
enumeration : (a -> Element msg) -> List a -> List (Element msg)
enumeration f xs =
    Helper.intersperseLastOneDifferent f (text ",") (text "and") xs


stripedList : List (Attribute msg) -> List (Attribute msg) -> List (Element msg) -> Element msg
stripedList attrCo attrCh children =
    column attrCo
        (List.indexedMap
            (\i ->
                el
                    (Background.color
                        (if i % 2 == 0 then
                            Styles.altBackgroundColor
                         else
                            Styles.alt2BackgroundColor
                        )
                        :: attrCh
                    )
            )
            children
        )


expandable : msg -> Bool -> List (Attribute msg) -> Element msg -> Element msg -> Element msg
expandable onExpand isExpanded attrs header content =
    let
        title isExpanded =
            Input.button attrs
                { label =
                    row
                        (attrs
                            ++ if isExpanded then
                                Styles.cardShadow 2
                               else
                                []
                        )
                        [ header
                        , if isExpanded then
                            Icons.normal Icons.arrowUp
                          else
                            Icons.normal Icons.arrowDown
                        ]
                , onPress = Just onExpand
                }
    in
        if isExpanded then
            column attrs [ title isExpanded, content ]
        else
            title isExpanded



-- Elements


siteLogo : String -> Element msg
siteLogo siteName =
    let
        letter =
            (if String.startsWith "www." (String.toLower siteName) then
                String.dropLeft 4 siteName
             else
                siteName
            )
                |> String.left 1
                |> String.toUpper
    in
        -- TODO: maybe use a service to get nice logos.
        -- For now just use the first letter on a nice background
        el
            [ Border.rounded 20
            , width (px 28)
            , height (px 28)
            , Background.color Styles.foregroundColor
            , Font.size 24
            , Font.center
            ]
            (Element.text letter)


hashIcon : String -> Element msg
hashIcon txt =
    el [ width (px 48) ] (html <| HashIcon.iconFromStringWithBrands 48 2.5 txt)


checkBox : (Bool -> msg) -> Bool -> String -> Bool -> Element msg
checkBox onChange isDisabled label checked =
    Input.checkbox []
        { onChange =
            if isDisabled then
                Nothing
            else
                Just onChange
        , icon =
            Just <|
                el
                    (List.concat
                        [ box
                        , [ padding (Styles.paddingScale 2) ]
                        , Styles.borderStyle
                        , [ (if isDisabled then
                                Styles.disabledColor
                             else if checked then
                                Styles.accentColor
                             else
                                Styles.white
                            )
                                |> Background.color
                          ]
                        , if checked then
                            [ inFront (el (paddingXY 2 0 :: box) (text "✔")) ]
                          else
                            []
                        ]
                    )
                    empty
        , checked = checked
        , label = Input.labelRight [] (text label)
        }


floatingButton : msg -> String -> Element msg
floatingButton msg txt =
    customPrimaryButton (Styles.cardShadow 3) (Just msg) txt


copyToClipboard : msg -> String -> Element msg
copyToClipboard msg txt =
    Input.button
        [ htmlAttribute (Attr.class "copy-to-clipboard")
        , htmlAttribute (Attr.attribute "data-txt" txt)
        ]
        { label =
            el
                (padding (Styles.paddingScale 1)
                    :: Styles.borderStyle
                )
                (text "Copy to clipboard")
        , onPress = Just msg
        }


box : List (Attribute msg)
box =
    [ width (px (Styles.scaled 1)), height (px (Styles.scaled 1)) ]


text : String -> Element msg
text txt =
    el [ Font.size (Styles.scaled 1), alignLeft ] (Element.text txt)


textWithCustomOverflow : String -> String -> Element msg
textWithCustomOverflow overflow txt =
    el [ Font.size (Styles.scaled 1), alignLeft, clipX, width fill ]
        (Element.html <|
            Html.div
                [ Attr.class "se text width-fill height-fill"

                -- Provides a ellipsis fallback, as only firefox supports custom text-overflow
                , Attr.attribute "style" <| "overflow: hidden; text-overflow: ellipsis; text-overflow: \"" ++ overflow ++ "\";"
                ]
                [ Html.text txt ]
        )


p : String -> Element msg
p txt =
    paragraph [] [ text txt ]


italicText : String -> Element msg
italicText txt =
    el [ Font.size (Styles.scaled 1), alignLeft, Font.italic ] (Element.text txt)


h1 : String -> Element msg
h1 txt =
    el [ Font.size (Styles.scaled 4), Font.bold, alignLeft ] (Element.text txt)


h2 : String -> Element msg
h2 txt =
    el [ Font.size (Styles.scaled 3), Font.bold, alignLeft ] (Element.text txt)


h3 : String -> Element msg
h3 txt =
    el [ Font.size (Styles.scaled 2), Font.bold, alignLeft ] (Element.text txt)


h4 : String -> Element msg
h4 txt =
    el [ Font.size (Styles.scaled 1), Font.bold, alignLeft ] (Element.text txt)


b : String -> Element msg
b txt =
    el [ Font.bold ] (text txt)


pageButton : msg -> Bool -> Page -> Element msg
pageButton onPress isActive page =
    Input.button [ width fill ]
        { onPress = Just onPress
        , label =
            column
                (if isActive then
                    [ Font.color Styles.accentColor
                    ]
                 else
                    []
                )
                [ el [ centerX ] (pageToIcon page)
                , if True || isActive then
                    el [ centerX ] (Route.pageToTitle page |> h4)
                  else
                    empty
                ]
        }


backButton : msg -> Element msg
backButton msg =
    Input.button [ width shrink ]
        { onPress = Just msg
        , label = row [] [ Icons.normal Icons.back, text "Back" ]
        }


pageToIcon : Page -> Element msg
pageToIcon page =
    case page of
        Home ->
            Icons.normal Icons.home

        Passwords ->
            Icons.normal Icons.passwords

        Devices ->
            Icons.normal Icons.devices

        Options ->
            Icons.normal Icons.options

        _ ->
            empty


primaryButton : Maybe msg -> String -> Element msg
primaryButton =
    customPrimaryButton []


customPrimaryButton : List (Attribute msg) -> Maybe msg -> String -> Element msg
customPrimaryButton attrs onPress txt =
    Input.button []
        { label =
            el
                (padding (Styles.paddingScale 1)
                    :: (Background.color <|
                            case onPress of
                                Nothing ->
                                    Styles.disabledColor

                                Just _ ->
                                    Styles.accentColor
                       )
                    :: Styles.borderStyle
                    ++ attrs
                )
                (text txt)
        , onPress = onPress
        }


customSelect : (Maybe a -> msg) -> (Bool -> a -> Element msg) -> (a -> Bool) -> List a -> List (Element msg)
customSelect onSelect renderElement isSelected elements =
    List.map
        (\a ->
            if isSelected a then
                customButton [ Background.color Styles.accentColor ] (Just (onSelect Nothing)) (renderElement True a)
            else
                customButton [] (Just (onSelect (Just a))) (renderElement False a)
        )
        elements


button : Maybe msg -> String -> Element msg
button onPress txt =
    Input.button []
        { label =
            el
                (padding (Styles.paddingScale 1)
                    :: (case onPress of
                            Nothing ->
                                Styles.disabledBorder

                            Just _ ->
                                Styles.borderStyle
                       )
                )
                (text txt)
        , onPress = onPress
        }


delete onPress =
    Input.button []
        { label =
            el (padding (Styles.paddingScale 1) :: Styles.borderStyle)
                (row [ spacing (Styles.paddingScale 0) ] [ Icons.small Icons.delete, text "Delete" ])
        , onPress = Just onPress
        }


deleteDanger onPress =
    Input.button []
        { label =
            el (padding (Styles.paddingScale 1) :: Styles.borderStyle ++ Styles.dangerStyle)
                (row [ spacing (Styles.paddingScale 0) ] [ Icons.small Icons.delete, text "Delete" ])
        , onPress = Just onPress
        }


dangerButton : Maybe msg -> String -> Element msg
dangerButton onPress txt =
    customButton Styles.dangerStyle onPress (text txt)


customButton : List (Attribute msg) -> Maybe msg -> Element msg -> Element msg
customButton attrs onPress inner =
    Input.button []
        { label =
            el
                (padding (Styles.paddingScale 1)
                    :: (case onPress of
                            Nothing ->
                                Styles.disabledBorder

                            Just _ ->
                                Styles.borderStyle
                       )
                    ++ attrs
                )
                inner
        , onPress = onPress
        }


toggleMoreButton : (Bool -> msg) -> String -> String -> Bool -> Element msg
toggleMoreButton onOpen labelClosed labelOpen isOpen =
    Input.checkbox [ padding (Styles.paddingScale 1) ]
        { onChange = Just onOpen
        , icon =
            Just <|
                text
                    (if isOpen then
                        "⌃"
                     else
                        "⌄"
                    )
        , checked = isOpen
        , label =
            Input.labelRight []
                (text
                    (if isOpen then
                        labelOpen
                     else
                        labelClosed
                    )
                )
        }


groupIcon : Bool -> Group -> Element msg
groupIcon isLocked ( ( level, _ ), post ) =
    row [ width shrink ]
        [ h3 (toString level)
        , if post == "" then
            empty
          else
            p ("(" ++ post ++ ")")
        , if isLocked then
            Icons.small Icons.locked
          else
            Icons.small Icons.unlocked
        ]


avatar : List (Attribute msg) -> Data.Device -> Element msg
avatar attrs { id, name, postFix } =
    row (spacing (Styles.scaled 1) :: attrs)
        [ hashIcon id
        , paragraph [ Styles.selectable, alignLeft, width fill, spacing (Styles.scaled -2) ]
            [ helperMayName name, helperMayIdPart postFix ]
        ]


helperMayName name =
    if name == "" then
        italicText "Unnamed"
    else
        text name


helperMayIdPart idPart =
    if idPart /= "" then
        italicText ("(" ++ idPart ++ ")")
    else
        empty


myAvatar : (String -> msg) -> String -> ( String, String ) -> List (Attribute msg) -> Element msg
myAvatar onSetDeviceName id ( name, idPart ) attrs =
    row (spacing (Styles.scaled 1) :: attrs)
        [ hashIcon id
        , row []
            [ inputText [] (Just onSetDeviceName) { placeholder = "Name your device..", label = "" } name
            , helperMayIdPart idPart
            ]
        ]


clampedNumberInput : (Int -> msg) -> String -> ( Int, Int, Int ) -> Int -> Element msg
clampedNumberInput onChange label ( min, default, max ) n =
    let
        m =
            clamp min max n

        toNumber s =
            String.toInt s |> Result.map (clamp min max) |> Result.withDefault default |> onChange

        inp att t pad =
            Input.text
                ([ Background.color Styles.transparent
                 , padding pad
                 , htmlAttribute (Attr.type_ t)
                 , htmlAttribute (Attr.min (toString min))
                 , htmlAttribute (Attr.max (toString max))
                 , htmlAttribute (Attr.value (toString m))
                 , Font.size (Styles.scaled 1)
                 , htmlAttribute (Attr.disabled (min == max))
                 ]
                    ++ att
                )
                { label = Input.labelAbove [] empty
                , onChange = Just toNumber
                , placeholder = Nothing
                , text = toString m
                }

        length =
            max - min

        numInp =
            inp [ width (px (14 + 14 * String.length (toString m))) ] "number" 5

        btn inc txt =
            customButton [] (Just (onChange (clamp min max (m + inc)))) (el [ width (px 24), Font.size (Styles.scaled 3) ] (text txt))
    in
        column [ height shrink ]
            [ el
                [ Font.size (Styles.scaled 1)
                , Font.bold
                ]
                (text label)
            , row
                [ padding (Styles.paddingScale 2)
                , spacing (Styles.paddingScale 1)

                -- , width (fillBetween { min = Nothing, max = Just 500 })
                ]
                (if length >= 6 then
                    [ inp [ width fill ] "range" 0, numInp ]
                 else
                    [ numInp, btn 1 "+", btn -1 "-" ]
                )
            ]


line : Element msg
line =
    el [ height (px 1), Background.color Styles.black, width fill ] empty


spacer : Element msg
spacer =
    el [ width fill ] empty


search : (String -> msg) -> String -> Element msg
search onChange value =
    inputHelper Input.search [] (Just onChange) "search" value



-- passwordEntry : Maybe (String -> msg) -> String -> Bool -> String -> Element msg
-- passwordEntry onChange label shouldShow value =
--     row []
--         [ el [ width (fillPortion 1), htmlAttribute (Attr.type_ "password"), htmlAttribute (Attr.name "password") ] (text label)
--         , password [ width (fillPortion 3) ] onChange shouldShow value
--         ]


table : List ( String, a -> Element msg ) -> List a -> Element msg
table headers data =
    Element.table [ spacing (Styles.paddingScale 1) ]
        { data = data
        , columns =
            List.map
                (\( h, fn ) ->
                    { header = h4 h
                    , view = fn
                    }
                )
                headers
        }


password attr onChange shouldShow value =
    Input.currentPassword (attr ++ textInputAttrs)
        -- (attr
        --     ++ [ padding 0
        --        , width shrink
        --        , htmlAttribute
        --             (Attr.size
        --                 (if shouldShow then
        --                     String.length value
        --                  else
        --                     5
        --                 )
        --             )
        --        ]
        -- )
        { onChange = onChange
        , text = value
        , label = textLabel "Password"
        , placeholder =
            Just <| Input.placeholder [ padding (Styles.paddingScale 1) ] (text "********")
        , show = shouldShow
        }


inputHelper fn attr onChange placeholder value =
    fn
        (attr
            ++ [ padding 0
               , htmlAttribute (Attr.disabled (onChange == Nothing))
               , htmlAttribute (Attr.size (max 15 (String.length value)))
               ]
        )
        { onChange = onChange
        , text = value
        , label = Input.labelLeft [ padding 0 ] empty
        , placeholder =
            if placeholder == "" then
                Nothing
            else
                Just <| Input.placeholder [ padding (Styles.paddingScale 1) ] (text placeholder)
        }


inputText : List (Attribute msg) -> Maybe (String -> msg) -> { label : String, placeholder : String } -> String -> Element msg
inputText attrs onMsg { placeholder, label } txt =
    Input.text (textInputAttrs ++ attrs)
        { label = textLabel label
        , onChange = onMsg
        , placeholder = Just (Input.placeholder [] (text placeholder))
        , text = txt
        }


textInputAttrs =
    [ Background.color Styles.transparent
    , Border.widthEach { bottom = 2, left = 0, right = 0, top = 0 }
    , Border.rounded 0
    , padding 0
    , width fill

    -- , hackInLineStyle "max-width" "500px"
    , hackInLineStyle "min-width" "0px"
    ]


textLabel label =
    Input.labelAbove
        [ Font.size (Styles.scaled 1)
        , Font.bold
        ]
        (if String.isEmpty label then
            empty
         else
            text label
        )
