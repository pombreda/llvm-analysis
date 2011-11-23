-- | This module implements the compositional pointer/escape analysis
-- described by Whaley and Rinard (http://doi.acm.org/10.1145/320384.320400).
--
-- This version is adapted to the LLVM IR (originally for Java).
module Data.LLVM.Analysis.Escape (
  -- * Types
  EscapeResult,
  EscapeGraph(..),
  EscapeNode(..),
  EscapeEdge(..),
  PTEGraph,
  -- * Functions
  runEscapeAnalysis,
  escapeGraphAtLocation
  ) where

import Algebra.Lattice
import Data.Graph.Inductive hiding ( Gr )
import Data.Map ( Map )
import qualified Data.Map as M
import Data.Set ( Set, (\\) )
import qualified Data.Set as S

import Data.LLVM
import Data.LLVM.CFG
import Data.LLVM.Analysis.Dataflow
import Data.LLVM.Internal.PatriciaTree

-- | The types of nodes in the graph
data EscapeNode = OParameterNode Value
                | OGlobalNode Value
                | OReturnNode Value
                | INode Value -- Allocas and allocators
                deriving (Eq)

-- | Edges labels for the points-to escape graph.  These differentiate
-- between internal and external edges.
data EscapeEdge = IEdge (Maybe String)
                | OEdge (Maybe String)
                deriving (Eq, Ord)

-- | A type synonym for the underlying points-to escape graph
type PTEGraph = Gr EscapeNode EscapeEdge

-- | The escape graph that is constructed for each program point.
-- They should all share considerable structure.
data EscapeGraph = EG { escapeGraph :: PTEGraph
                      , escapeCalleeMap :: Map Node (Set Instruction)
                      , escapeReturns :: Set Node
                      }

instance Eq EscapeGraph where
  eg1 == eg2 = escapeReturns eg1 == escapeReturns eg2 &&
               escapeCalleeMap eg1 == escapeCalleeMap eg2 &&
               (escapeGraph eg1 `equal` escapeGraph eg2)

instance MeetSemiLattice EscapeGraph where
  meet = egMeet

egMeet :: EscapeGraph -> EscapeGraph -> EscapeGraph
egMeet eg1 eg2 = EG { escapeGraph = g'
                    , escapeCalleeMap = ecm
                    , escapeReturns = er
                    }
  where
    ecm = M.unionWith S.union (escapeCalleeMap eg1) (escapeCalleeMap eg2)
    er = escapeReturns eg1 `S.union` escapeReturns eg2
    e1 = S.fromList $ labEdges (escapeGraph eg1)
    e2 = S.fromList $ labEdges (escapeGraph eg2)
    newEs = S.toList $ e2 \\ e1
    -- Insert new edges from eg2 into eg1
    g' = insEdges newEs (escapeGraph eg1)

instance BoundedMeetSemiLattice EscapeGraph where
  top = EG { escapeGraph = mkGraph [] []
           , escapeCalleeMap = M.empty
           , escapeReturns = S.empty
           }

instance DataflowAnalysis EscapeGraph where
  transfer = escapeTransfer

-- | The transfer function to add/remove edges to the points-to escape
-- graph for each instruction.
escapeTransfer :: EscapeGraph -> Instruction -> [CFGEdge] -> EscapeGraph
escapeTransfer = undefined

-- | An opaque result type for the analysis.  Use
-- @escapeGraphAtLocation@ to access it.
newtype EscapeResult = ER (Map Function (Instruction -> EscapeGraph))

-- | An accessor to retrieve the @EscapeGraph@ for any program point.
escapeGraphAtLocation :: EscapeResult -> Instruction -> EscapeGraph
escapeGraphAtLocation (ER er) i = mapping i
  where
    Just bb = instructionBasicBlock i
    f = basicBlockFunction bb
    mapping = M.findWithDefault (error "No escape result for function") f er

-- | Run the Whaley-Rinard escape analysis on a Module.  This returns
-- an opaque result that can be accessed via @escapeGraphAtLocation@.
runEscapeAnalysis :: Module -> EscapeResult
runEscapeAnalysis m = ER $! M.fromList mapping
  where
    funcLookups = map (uncurry forwardDataflow) statesAndCFGs
    mapping = zip fs funcLookups

    fs = moduleDefinedFunctions m
    globalGraph = buildBaseGlobalGraph m
    cfgs = map mkCFG fs
    states = map (mkInitialGraph globalGraph) fs
    statesAndCFGs = zip states cfgs

-- FIXME: Also need to identify new objects returned by allocators.
-- This is kind of nice because we don't need explicit information
-- about this library - only dependencies.  The escape analysis will
-- essentially identify allocators for us.
--
-- FIXME: Add field nodes

-- | Build the initial EscapeGraph <O_0, I_0, e_0, r_0> for the given
-- Function.
mkInitialGraph :: PTEGraph -> Function -> EscapeGraph
mkInitialGraph globalGraph f =
  EG { escapeGraph = g, escapeCalleeMap = M.empty, escapeReturns = S.empty }
  where
    g = insNodes nods globalGraph
    mkCtxt ctor v = (valueUniqueId v, ctor v)
    nods = concat [ paramNodes, returnNodes, insideNodes {-, fieldNodes -} ]
    insts = concatMap basicBlockInstructions (functionBody f)
    paramNodes = map (mkCtxt OParameterNode . Value) (functionParameters f)
    returnNodes = map (mkCtxt OReturnNode . Value) $ filter isNonVoidCall insts
    insideNodes = map (mkCtxt INode . Value) $ filter isInternal insts

isNonVoidCall :: Instruction -> Bool
isNonVoidCall inst = case inst of
  CallInst { instructionType = TypeVoid } -> False
  CallInst {} -> True
  InvokeInst { instructionType = TypeVoid } -> False
  InvokeInst {} -> True
  _ -> False

isInternal :: Instruction -> Bool
isInternal inst = case inst of
  AllocaInst {} -> True
  _ -> False

-- | Construct the base graph that contains all of the global nodes in
-- the program.  The hope is that by having a common base graph, some
-- of the common structure can be shared.
buildBaseGlobalGraph :: Module -> PTEGraph
buildBaseGlobalGraph m = mkGraph nodes0 []
  where
    globals = map Value $ moduleGlobalVariables m
    externs = map Value $ moduleExternalValues m
    nodes0 = map mkNod $ globals ++ externs
    mkNod v = (valueUniqueId v, OGlobalNode v)