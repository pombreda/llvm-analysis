module Data.LLVM.Private.PlaceholderTypes ( Identifier(..)
                                          , Value(..)
                                          , ValueT(..)
                                          , ConstantT(..)
                                          , TypedValue(..)
                                          , ArithFlag(..)
                                          ) where

import Data.ByteString.Lazy (ByteString)
import Data.LLVM.Private.AttributeTypes

-- These types are generated by the parser and will be
-- *temporary*.  They reference strings since that is all we have at
-- parse time.  These types will be replaced by direct references
-- after the entire AST is built and we can build the self-referential
-- graph structure.

data Identifier = LocalIdentifier ByteString
                | GlobalIdentifier ByteString
                  deriving (Show, Eq)

data Value = Value { valueName :: Identifier
                   , valueType :: Type
                   , valueContent :: ValueT
                   }
           | UnnamedValue ValueT
           | ConstantValue ConstantT
             -- { constantType :: Type
             --               , constantContent :: ConstantT
             --               }
           deriving (Show)

data TypedValue = TypedValue Type Value
                deriving (Show)
-- The first group of value types are unusual and are *not* "users".
-- This distinction is not particularly important for my purposes,
-- though, so I'm just giving all values a list of operands (which
-- will be empty for these things)
data ValueT = Argument [ParamAttribute]
            | BasicBlock ByteString [Value] -- Label, really instructions, which are values
            | InlineAsm ByteString ByteString -- ASM String, Constraint String; can parse constraints still
            | RetInst (Maybe TypedValue)
            | UnconditionalBranchInst ByteString
            | BranchInst TypedValue ByteString ByteString
            | SwitchInst TypedValue ByteString [(TypedValue, ByteString)]
            | IndirectBranchInst TypedValue [Value]
              -- InvokeInst
            | UnwindInst
            | UnreachableInst
            | AddInst [ArithFlag] Value Value
            | SubInst [ArithFlag] Value Value
            | MulInst [ArithFlag] Value Value
            | DivInst Value Value -- Does not encode the exact flag of sdiv.  Convince me to
            | RemInst Value Value
            | ShlInst Value Value
            | LshrInst Value Value
            | AshrInst Value Value
            | AndInst Value Value
            | OrInst Value Value
            | XorInst Value Value
            | ExtractElementInst Value Value
            | InsertElementInst Value Value Value
            | ShuffleVectorInst Value Value Value
              -- FIXME: extractvalue
            | InsertValueInst Value Value Integer
            | AllocaInst Type Value Integer -- Type, NumElems, align
            | LoadInst Bool Type Value Integer -- Volatile? Type Dest align
            | StoreInst Bool Type Value Integer -- Volatile? Type Dest align
            | TruncInst Value Type -- The value being truncated, and the type truncted to
            | ZExtInst Value Type
            | SExtInst Value Type
            | FPTruncInst Value Type
            | FPExtInst Value Type
            | FPToUIInst Value Type
            | FPToSIInst Value Type
            | UIToFPInst Value Type
            | SIToFPInst Value Type
            | PtrToIntInst Value Type
            | IntToPtrInst Value Type
            | BitcastInst Value Type
            | ICmpInst ICmpCondition Value Value
            | FCmpInst FCmpCondition Value Value
            deriving (Show)

data ArithFlag = AFNSW | AFNUW deriving (Show)

-- FIXME: Convert the second ident to a Value (basic blocks are values)
data ConstantT = BlockAddress Identifier Identifier -- Func Ident, Block Label -- to be resolved into something useful later
               | ConstantAggregateZero
               | ConstantArray [TypedValue] -- This should have some parameters but I don't know what
               | ConstantExpr Value -- change this to something else maybe?  Value should suffice... might even eliminate this one
               | ConstantFP Double
               | ConstantInt Integer
               | ConstantPointerNull
               | ConstantStruct [TypedValue] -- Just a list of other constants
               | ConstantVector [TypedValue] -- again
               | UndefValue
               | MDNode [Value] -- A list of constants (and other metadata)
               | MDString ByteString
               | Function [Value] [FunctionAttribute] [ValueT] -- Arguments, function attrs, block list
               | GlobalVariable VisibilityStyle LinkageType ByteString
               | GlobalAlias VisibilityStyle LinkageType ByteString Value -- new name, real var
               | ConstantIdentifier Identifier -- Wrapper for globals - to be resolved later into a more useful direct references to a GlobalVariable
               deriving (Show)
