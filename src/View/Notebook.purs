module View.Notebook (view) where

import Control.Apply ((*>))
import Control.Functor (($>))
import Control.Monad.Eff.Class (liftEff)
import Control.Plus (empty)
import Controller.Notebook (handleMenuSignal, handleSubmitName)
import Data.Array ((..), length, zipWith, replicate, sort)
import Data.Bifunctor (bimap)
import Data.Inject1 (inj)
import Data.Int (toNumber, fromNumber, Int())
import Data.Maybe (maybe)
import Data.Path.Pathy
import Data.String (joinWith)
import Driver.File.Path (updatePath)
import Model.Notebook
import Model.Notebook.Cell
import Model.Notebook.Domain (_notebookCells)
import Input.Notebook (NotebookInput(..), runCellEvent)
import Model.Notebook.Menu (DropdownItem(), MenuElement(), MenuInsertSignal(..))
import Optic.Core ((^.))
import View.Common (contentFluid, navbar, icon, logo, glyph, row)
import View.Notebook.Cell (cell)
import View.Notebook.Common (HTML())
import qualified Config as Config
import qualified Data.Argonaut.Encode as Ae
import qualified Data.Argonaut.Printer as Ap
import qualified Halogen.HTML as H
import qualified Halogen.HTML.Attributes as A
import qualified Halogen.HTML.Events as E
import qualified Halogen.HTML.Events.Forms as E
import qualified Halogen.HTML.Events.Handler as E
import qualified Halogen.HTML.Events.Monad as E
import qualified Halogen.Themes.Bootstrap3 as B
import qualified Math as Math
import qualified View.Css as Vc
import qualified View.File.Modal.Common as Vm
import View.Notebook.Cell.Search (searchOutput)
import Model.Resource (resourceDir, resourceFileName)

view :: forall e. State -> HTML e
view state =
  H.div [ E.onClick (E.input_ $ inj CloseDropdowns) ]
  (navigation state <> body state <> modal state)

navigation :: forall e. State -> [HTML e]
navigation state =
  if not state.editable
  then []
  else
    [ navbar
      [ H.div [ A.classes [ Vc.navCont, Vc.notebookNav, B.containerFluid ] ]
        [ icon B.glyphiconBook $ notebookHref state
        , logo
        , name state ]
      , H.ul [ A.classes [ B.nav, B.navbarNav ] ]
        ( zipWith (li state) (0 .. length state.dropdowns) state.dropdowns )
      ] ]
  where
  notebookHref :: State -> String
  notebookHref state =
    let u = maybe rootDir (rootDir </>) $
        sandbox rootDir $ resourceDir state.resource
    in updatePath (pure u) Config.homeHash

body :: forall e. State -> [HTML e]
body state =
  [ if not state.loaded
    then H.h1 [ A.classes [ B.textCenter ] ] [ H.text "Loading..." ]
    else if state.error /= ""
         then H.div [ A.classes [ B.alert, B.alertDanger ] ]
              [ H.h1 [ A.classes [ B.textCenter ] ] [ H.text state.error ] ]
         else contentFluid
              [ H.div [ A.class_ B.clearfix ]
                (cells state <>
                 (if state.editable
                  then newCellMenu state
                  else []))] ]

cells :: forall e. State -> [HTML e]
cells state = [ H.div [ A.classes [ Vc.notebookContent ] ]
                ((sort $ state ^. _notebook <<< _notebookCells) >>= cell state.tickDate) ]

margined :: forall e. [HTML e] -> [HTML e] -> HTML e
margined l r = row [ H.div [ A.classes [ B.colMd2 ] ] l
                      , H.div [ A.classes [ B.colMd10 ] ] r
                      ]

newCellMenu :: forall e. State -> [HTML e]
newCellMenu state =
  [ H.a [ A.href "#"
        , A.classes [ B.btn, B.btnLink, B.btnLg, Vc.notebookAddCellButton ]
        , E.onClick (\_ -> E.stopPropagation *>
                           E.preventDefault $>
                           (pure $ inj $ SetAddingCell (not state.addingCell))) ]
    [ glyph B.glyphiconPlusSign ]
  , H.div [ A.classes [ B.clearfix ] ] []
  , H.div [ E.onClick (\_ -> E.stopPropagation $> empty)
          , A.classes ([ B.panel
                       , B.panelDefault
                       , B.fade
                       , Vc.notebookAddCellMenu ] <>
                       if state.addingCell
                       then [B.in_]
                       else [])]
    [ H.div [ A.classes [ B.panelBody ] ]
      [ H.ul [ A.classes [ B.listInline ] ]
        [ li QueryInsert B.glyphiconHdd
        , li MarkdownInsert B.glyphiconEdit
        , li SearchInsert B.glyphiconSearch ] ] ] ]
  where
  li :: MenuInsertSignal -> A.ClassName -> HTML e
  li inp cls =
    H.li_ [ H.a [ A.href "#"
                , E.onClick (\e -> do
                                E.stopPropagation
                                E.preventDefault $> do
                                  (handleMenuSignal state) <<< inj $ inp ) ]
            [ glyph cls ] ]


txt :: forall e. Int -> String -> [HTML e]
txt lvl text =
  [ H.text $ (joinWith "" $ replicate (toNumber lvl) "--") <> " " <> text ]


li :: forall e. State -> Number ->  DropdownItem -> HTML e
li state i {visible: visible, name: name, children: children} =
  H.li [ E.onClick (\ev -> do E.stopPropagation
                              E.input_ (inj $ Dropdown i) ev)
       , A.classes $ [ B.dropdown ] <>
         (if visible then [ B.open ] else [ ]) ]
  [ H.a [ A.href "#"
        , E.onClick (\_ -> E.preventDefault $> empty)] (txt (fromNumber 0) name)
  , H.ul [ A.classes [ B.dropdownMenu ] ]
    (menuItem state <$> children) ]

menuItem :: forall e. State -> MenuElement -> HTML e
menuItem state {name: name, message: mbMessage, lvl: lvl} =
  H.li [ A.classes (maybe [B.disabled] (const []) mbMessage) ]
  [ H.a [ A.href "#"
        , E.onClick (\e -> do
                        E.stopPropagation
                        E.preventDefault $>
                          maybe empty (handleMenuSignal state) mbMessage) ]
    [H.span_ $ (txt lvl name) <>
     (maybe [glyph B.glyphiconChevronRight] (const []) mbMessage) ]]


name :: forall e. State -> HTML e
name state =
  H.div [ A.classes [ B.colXs12, B.colSm8 ] ]
  [ H.input [ A.classes [ Vc.notebookName ]
            , A.id_ Config.notebookNameEditorId
            , E.onInput (E.input $ inj <<< SetName)
            , E.onKeyUp (\e -> if e.keyCode == 13 then
                                 pure $ handleSubmitName state
                               else pure empty)
            , A.value (resourceFileName state.resource)  ] [] ]

modal :: forall e. State -> [HTML e]
modal state =
  [ H.div [ A.classes ([B.modal, B.fade] <> if state.modalError /= ""
                                            then [B.in_]
                                            else [])
          , E.onClick (E.input_ $ inj $ SetModalError "") ]
    [ H.div [ A.classes [ B.modalDialog ] ]
      [ H.div [ A.classes [ B.modalContent ] ]
        [ Vm.header $ Vm.h4 "Error"
        , Vm.body
          [ H.div [ A.classes [ B.alert, B.alertDanger ] ]
            [ H.text state.modalError ] ]
        ]
      ]
    ]
  ]

