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

module SlamData.Workspace.Card.Setups.Chart.Pie.Model where

import SlamData.Prelude

import Data.Argonaut (JCursor, Json, decodeJson, (~>), (:=), isNull, jsonNull, (.?), jsonEmptyObject)
import Data.Lens ((^.))

import SlamData.Workspace.Card.Setups.Chart.Aggregation as Ag

import Test.StrongCheck.Arbitrary (arbitrary)
import Test.StrongCheck.Gen as Gen
import Test.StrongCheck.Data.Argonaut (runArbJCursor)

import SlamData.Workspace.Card.Setups.Chart.Aggregation (Aggregation, nonMaybeAggregationSelect)
import SlamData.Workspace.Card.Setups.Behaviour as SB
import SlamData.Workspace.Card.Setups.Axis as Ax
import SlamData.Form.Select as S
import SlamData.Form.Select ((⊝))


type PieR =
  { category ∷ JCursor
  , value ∷ JCursor
  , valueAggregation ∷ Ag.Aggregation
  , donut ∷ Maybe JCursor
  , parallel ∷ Maybe JCursor
  }

type Model = Maybe PieR

initialModel ∷ Model
initialModel = Nothing

eqPieR ∷ PieR → PieR → Boolean
eqPieR r1 r2 =
  r1.category ≡ r2.category
  ∧ r1.value ≡ r2.value
  ∧ r1.valueAggregation ≡ r2.valueAggregation
  ∧ r1.donut ≡ r2.donut
  ∧ r1.parallel ≡ r2.parallel

eqModel ∷ Model → Model → Boolean
eqModel Nothing Nothing = true
eqModel (Just r1) (Just r2) = eqPieR r1 r2
eqModel _ _ = false

genModel ∷ Gen.Gen Model
genModel = do
  isNothing ← arbitrary
  if isNothing
    then pure Nothing
    else map Just do
    category ← map runArbJCursor arbitrary
    value ← map runArbJCursor arbitrary
    valueAggregation ← arbitrary
    donut ← map (map runArbJCursor) arbitrary
    parallel ← map (map runArbJCursor) arbitrary
    pure { category
         , value
         , valueAggregation
         , donut
         , parallel
         }

encode ∷ Model → Json
encode Nothing = jsonNull
encode (Just r) =
  "configType" := "pie"
  ~> "category" := r.category
  ~> "value" := r.value
  ~> "valueAggregation" := r.valueAggregation
  ~> "donut" := r.donut
  ~> "parallel" := r.parallel
  ~> jsonEmptyObject

decode ∷ Json → String ⊹ Model
decode js
  | isNull js = pure Nothing
  | otherwise = map Just do
    obj ← decodeJson js
    configType ← obj .? "configType"
    unless (configType ≡ "pie")
      $ throwError "This config is not pie"
    category ← obj .? "category"
    value ← obj .? "value"
    valueAggregation ← obj .? "valueAggregation"
    donut ← obj .? "donut"
    parallel ← obj .? "parallel"
    pure { category, value, valueAggregation, donut, parallel }

type ReducedState r =
  { axes ∷ Ax.Axes
  , category ∷ S.Select JCursor
  , value ∷ S.Select JCursor
  , valueAgg ∷ S.Select Aggregation
  , donut ∷ S.Select JCursor
  , parallel ∷ S.Select JCursor
  | r}

initialState ∷ ReducedState ()
initialState =
  { axes: Ax.initialAxes
  , category: S.emptySelect
  , value: S.emptySelect
  , valueAgg: S.emptySelect
  , donut: S.emptySelect
  , parallel: S.emptySelect
  }


behaviour ∷ ∀ r. SB.Behaviour (ReducedState r) Model
behaviour =
  { synchronize
  , load
  , save
  }
  where
  synchronize st =
    let
      newValue =
        S.setPreviousValueFrom (Just st.value)
          $ S.autoSelect
          $ S.newSelect
          $ st.axes.value

      newValueAggregation =
        S.setPreviousValueFrom (Just st.valueAgg)
          $ nonMaybeAggregationSelect

      newCategory =
        S.setPreviousValueFrom (Just st.category)
          $ S.autoSelect
          $ S.newSelect
          $ st.axes.category
          ⊕ st.axes.time
          ⊕ st.axes.date
          ⊕ st.axes.datetime

      newDonut =
        S.setPreviousValueFrom (Just st.donut)
          $ S.newSelect
          $ S.ifSelected [newCategory]
          $ st.axes.category
          ⊕ st.axes.time
          ⊝ newCategory

      newParallel =
        S.setPreviousValueFrom (Just st.parallel)
          $ S.newSelect
          $ S.ifSelected [newCategory]
          $ st.axes.category
          ⊕ st.axes.time
          ⊝ newCategory
          ⊝ newDonut
    in
      st{ value = newValue
        , valueAgg = newValueAggregation
        , category = newCategory
        , donut = newDonut
        , parallel = newParallel
        }

  load Nothing st = st
  load (Just m) st =
    st{ value = S.fromSelected $ Just m.value
      , valueAgg = S.fromSelected $ Just m.valueAggregation
      , category = S.fromSelected $ Just m.category
      , donut = S.fromSelected m.donut
      , parallel = S.fromSelected m.parallel
      }

  save st =
    { value: _
    , valueAggregation: _
    , category: _
    , parallel: st.parallel ^. S._value
    , donut: st.donut ^. S._value
    }
    <$> (st.value ^. S._value)
    <*> (st.valueAgg ^. S._value)
    <*> (st.category ^. S._value)
