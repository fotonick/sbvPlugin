{-# OPTIONS_GHC -fplugin=Data.SBV.Plugin #-}

module T25 where

import Data.SBV.Plugin

{-# ANN f theorem #-}
f :: Bool
f = True
