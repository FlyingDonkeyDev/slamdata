{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Workspace.Routing
  ( routing
  , Routes(..)
  , mkWorkspaceHash
  , mkWorkspaceURL
  ) where

import SlamData.Prelude

import Data.Foldable as F
import Data.List as L
import Data.Map as Map
import Data.Maybe.Unsafe as MU
import Data.Path.Pathy ((</>))
import Data.Path.Pathy as P
import Data.String.Regex as R
import Data.StrMap as SM

import Routing.Match (Match)
import Routing.Match (eitherMatch, list) as Match
import Routing.Match.Class (lit, str, params) as Match

import SlamData.Config as Config
import SlamData.Workspace.AccessType (AccessType(..))
import SlamData.Workspace.Action as NA
import SlamData.Workspace.Card.Port.VarMap as Port
import SlamData.Workspace.Deck.DeckId as D

import Text.Parsing.Parser (runParser)

import Utils.Path as UP

data Routes
  = ExploreRoute UP.FilePath
  | WorkspaceRoute UP.DirPath (L.List D.DeckId) NA.Action Port.VarMap

routing :: Match Routes
routing
  =   ExploreRoute <$> (oneSlash *> Match.lit "explore" *> explored)
  <|> WorkspaceRoute <$> workspace <*> deckIds <*> action <*> optionalVarMap

  where
  optionalVarMap :: Match Port.VarMap
  optionalVarMap = varMap <|> pure SM.empty

  varMap :: Match Port.VarMap
  varMap = Match.params <#> Map.toList >>> foldl go SM.empty
    where
      go m (Tuple k str) =
        case runParser str Port.parseVarMapValue of
          Left err -> m
          Right v -> SM.insert k v m

  oneSlash :: Match Unit
  oneSlash = Match.lit ""

  explored :: Match UP.FilePath
  explored = Match.eitherMatch $ mkResource <$> Match.list Match.str

  mkResource :: L.List String -> Either String UP.FilePath
  mkResource parts =
    case L.last parts of
      Just filename | filename /= "" ->
        let dirParts = MU.fromJust (L.init parts)
            filePart = P.file filename
            path = foldr (\part acc -> P.dir part </> acc) filePart dirParts
        in Right $ P.rootDir </> path
      _ -> Left "Expected non-empty explore path"

  workspace :: Match UP.DirPath
  workspace = workspaceFromParts <$> partsAndName

  workspaceFromParts :: Tuple (L.List String) String -> UP.DirPath
  workspaceFromParts (Tuple ps nm) =
    foldl (</>) P.rootDir (map P.dir ps) </> P.dir nm

  partsAndName :: Match (Tuple (L.List String) String)
  partsAndName = Tuple <$> (oneSlash *> Match.list notName) <*> name

  name :: Match String
  name = Match.eitherMatch $ map workspaceName Match.str

  notName :: Match String
  notName = Match.eitherMatch $ map pathPart Match.str

  workspaceName :: String -> Either String String
  workspaceName input
    | checkExtension input = Right input
    | otherwise = Left input

  pathPart :: String -> Either String String
  pathPart input
    | input == "" || checkExtension input = Left "incorrect path part"
    | otherwise = Right input

  extensionRegex :: R.Regex
  extensionRegex = R.regex ("\\." <> Config.workspaceExtension <> "$") R.noFlags

  checkExtension :: String -> Boolean
  checkExtension = R.test extensionRegex

  deckIds :: Match (L.List D.DeckId)
  deckIds = Match.list $ Match.eitherMatch $ map D.stringToDeckId Match.str

  action :: Match NA.Action
  action
      = (Match.eitherMatch $ map NA.parseAction Match.str)
    <|> pure (NA.Load ReadOnly)

-- TODO: it would be nice if `purescript-routing` had a way to render a route
-- from a matcher, so that we could do away with the following brittle functions.

-- Currently the only place where modules from `Workspace.Model` are used
-- is `Controller.File`. I think that it would be better if url will be constructed
-- from things that are already in `FileSystem` (In fact that using of
-- `workspaceURL` is redundant, because (state ^. _path) is `DirPath`
-- `theseRight $ That Config.newWorkspaceName` ≣ `Just Config.newWorkspaceName`
mkWorkspaceURL
  :: UP.DirPath    -- workspace path
  -> NA.Action     -- workspace action
  -> String
mkWorkspaceURL path action =
  Config.workspaceUrl
    <> mkWorkspaceHash path action SM.empty

mkWorkspaceHash
  :: UP.DirPath    -- workspace path
  -> NA.Action     -- workspace action
  -> Port.VarMap   -- global `VarMap`
  -> String
mkWorkspaceHash path action varMap =
  "#"
    <> UP.encodeURIPath (P.printPath path)
    <> NA.printAction action
    <> maybe "" ("/" <> _)  (renderVarMapQueryString varMap)

renderVarMapQueryString
  :: Port.VarMap -- global `VarMap`
  -> Maybe String
renderVarMapQueryString varMap =
  if SM.isEmpty varMap
     then Nothing
     else Just $ "?" <> F.intercalate "&" (varMapComponents varMap)
  where
    varMapComponents =
      SM.foldMap $ \key val ->
        [ key
            <> "="
            <> Global.encodeURIComponent (Port.renderVarMapValue val)
        ]
