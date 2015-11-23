---------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Plugin.Env
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- The environment for mapping concrete functions/types to symbolic ones.
-----------------------------------------------------------------------------

{-# LANGUAGE TemplateHaskell #-}

module Data.SBV.Plugin.Env (buildFunEnv, buildTCEnv) where

import GhcPlugins
import qualified Language.Haskell.TH as TH

import qualified Data.Map as M

import Data.Int
import Data.Word
import Data.Maybe (fromMaybe)

import qualified Data.SBV         as S hiding (proveWith, proveWithAny)
import qualified Data.SBV.Dynamic as S

import Data.SBV.Plugin.Common

-- | Build the initial environment containing types
buildTCEnv :: CoreM (M.Map TyCon S.Kind)
buildTCEnv = M.fromList `fmap` mapM grabTyCon [ (S.KBool,             ''Bool)
                                              , (S.KUnbounded,        ''Integer)
                                              , (S.KFloat,            ''Float)
                                              , (S.KDouble,           ''Double)
                                              , (S.KBounded True   8, ''Int8)
                                              , (S.KBounded True  16, ''Int16)
                                              , (S.KBounded True  32, ''Int32)
                                              , (S.KBounded True  64, ''Int64)
                                              , (S.KBounded False  8, ''Word8)
                                              , (S.KBounded False 16, ''Word16)
                                              , (S.KBounded False 32, ''Word32)
                                              , (S.KBounded False 64, ''Word64)
                                              ]
  where grabTyCon (k, x) = do Just fn <- thNameToGhcName x
                              tc <- lookupTyCon fn
                              return (tc, k)

-- | Build the initial environment containing functions
buildFunEnv :: CoreM (M.Map (Id, S.Kind) Val)
buildFunEnv = M.fromList `fmap` mapM grabVar symFuncs
  where grabVar (n, k, sfn) = do Just fn <- thNameToGhcName n
                                 f <- lookupId fn
                                 return ((f, k), sfn)

-- | Symbolic functions supported by the plugin
symFuncs :: [(TH.Name, S.Kind, Val)]
symFuncs =  -- equality is for all kinds
          [('(==), k, lift2 S.svEqual) | k <- allKinds]

          -- arithmetic
       ++ [(op, k, lift1 sOp) | k <- arithKinds, (op, sOp) <- unaryOps]
       ++ [(op, k, lift2 sOp) | k <- arithKinds, (op, sOp) <- binaryOps]

          -- literal conversions from Integer
       ++ [(op, k, lift1Int sOp) | k <- integerKinds, (op, sOp) <- [('fromInteger, S.svInteger k)]]

          -- comparisons
       ++ [(op, k, lift2 sOp) | k <- arithKinds, (op, sOp) <- compOps ]
 where
       -- Bit-vectors
       bvKinds    = [S.KBounded s sz | s <- [False, True], sz <- [8, 16, 32, 64]]

       -- Integer kinds
       integerKinds = S.KUnbounded : bvKinds

       -- Float kinds
       floatKinds = [S.KFloat, S.KDouble]

       -- All arithmetic kinds
       arithKinds = floatKinds ++ integerKinds

       -- Everything
       allKinds   = S.KBool : arithKinds

       -- Unary arithmetic ops
       unaryOps   = [ ('abs, S.svAbs)
                    ]

       -- Binary arithmetic ops
       binaryOps  = [ ('(+), S.svPlus)
                    , ('(-), S.svMinus)
                    , ('(*), S.svTimes)
                    ]

       -- Comparisons
       compOps    = [ ('(<),  S.svLessThan)
                    , ('(>),  S.svGreaterThan)
                    , ('(<=), S.svLessEq)
                    , ('(>=), S.svGreaterEq)
                    ]

-- | Lift a unary SBV function to the plugin value space
lift1 :: (S.SVal -> S.SVal) -> Val
lift1 f = Func $ \(Base a) -> Base (f a)

-- | Lift a unary SBV function that takes and integer value to the plugin value space
lift1Int :: (Integer -> S.SVal) -> Val
lift1Int f = Func $ \(Base i) -> Base (f (fromMaybe (error ("Cannot extract an integer from value: " ++ show i)) (S.svAsInteger i)))

-- | Lift a two argument SBV function to our the plugin value space
lift2 :: (S.SVal -> S.SVal -> S.SVal) -> Val
lift2 f = Func $ \(Base a) -> Func $ \(Base b) -> Base (f a b)
