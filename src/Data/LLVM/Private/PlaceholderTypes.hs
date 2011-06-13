module Data.LLVM.Private.PlaceholderTypes ( Instruction(..)
                                          , InstructionT(..)
                                          , Constant(..)
                                          , ConstantT(..)
                                          , Module(..)
                                          , GlobalDeclaration(..)
                                          , BasicBlock(..)
                                          , FormalParameter(..)
                                          , Type(..)
                                          , PartialConstant
                                          , voidInst
                                          , namedInst
                                          , maybeNamedInst
                                          , valueRef
                                          ) where

import Data.ByteString.Char8 ( ByteString )

import Data.LLVM.Private.AttributeTypes

-- These types are generated by the parser and will be
-- *temporary*.  They reference strings since that is all we have at
-- parse time.  These types will be replaced by direct references
-- after the entire AST is built and we can build the self-referential
-- graph structure.

data Instruction = Instruction { instName :: Maybe Identifier
                               , instType :: Type
                               , instContent :: InstructionT
                               , instMetadata :: Maybe Identifier
                               }
                   -- This variant is used if we can't build the type
                   -- yet.  It can be resolved after everything is
                   -- made properly referential.  This is useful for
                   -- getelementptr and extractvalue.
                 | UnresolvedInst { unresInstName :: Maybe Identifier
                                  , unresInstContent :: InstructionT
                                  , unresInstMetadata :: Maybe Identifier
                                  }
           deriving (Show, Eq)

type PartialConstant = Type -> Constant

voidInst :: InstructionT -> Instruction
voidInst v = Instruction { instName = Nothing
                         , instType = TypeVoid
                         , instContent = v
                         , instMetadata = Nothing
                         }

namedInst :: Identifier -> Type -> InstructionT -> Instruction
namedInst i t v = Instruction { instName = Just i
                              , instType = t
                              , instContent = v
                              , instMetadata = Nothing
                              }

maybeNamedInst :: Maybe Identifier -> Type -> InstructionT -> Instruction
maybeNamedInst i t v = Instruction { instName = i
                                   , instType = t
                                   , instContent = v
                                   , instMetadata = Nothing
                                   }

data Constant = ConstValue ConstantT Type
              | ValueRef Identifier
              deriving (Show, Eq)

valueRef :: Identifier -> a -> Constant
valueRef ident = const (ValueRef ident)

-- The first group of value types are unusual and are *not* "users".
-- This distinction is not particularly important for my purposes,
-- though, so I'm just giving all values a list of operands (which
-- will be empty for these things)
data InstructionT = RetInst (Maybe Constant)
            | UnconditionalBranchInst Constant
            | BranchInst Constant Constant Constant
            | SwitchInst Constant Constant [(Constant, Constant)]
            | IndirectBranchInst Constant [Constant]
            | UnwindInst
            | UnreachableInst
            | AddInst [ArithFlag] Constant Constant
            | SubInst [ArithFlag] Constant Constant
            | MulInst [ArithFlag] Constant Constant
            | DivInst Constant Constant -- Does not encode the exact flag of sdiv.  Convince me to
            | RemInst Constant Constant
            | ShlInst Constant Constant
            | LshrInst Constant Constant
            | AshrInst Constant Constant
            | AndInst Constant Constant
            | OrInst Constant Constant
            | XorInst Constant Constant
            | ExtractElementInst Constant Constant
            | InsertElementInst Constant Constant Constant
            | ShuffleVectorInst Constant Constant Constant
            | ExtractValueInst Constant [Integer]
            | InsertValueInst Constant Constant [Integer]
            | AllocaInst Type Constant Integer -- Type, NumElems, align
            | LoadInst Bool Constant Integer -- Volatile? Type Dest align
            | StoreInst Bool Constant Constant Integer -- Volatile? Type Dest align
            | TruncInst Constant Type -- The value being truncated, and the type truncted to
            | ZExtInst Constant Type
            | SExtInst Constant Type
            | FPTruncInst Constant Type
            | FPExtInst Constant Type
            | FPToUIInst Constant Type
            | FPToSIInst Constant Type
            | UIToFPInst Constant Type
            | SIToFPInst Constant Type
            | PtrToIntInst Constant Type
            | IntToPtrInst Constant Type
            | BitcastInst Constant Type
            | ICmpInst ICmpCondition Constant Constant
            | FCmpInst FCmpCondition Constant Constant
            | PhiNode [(Constant, Constant)]
            | SelectInst Constant Constant Constant
            | GetElementPtrInst Bool Constant [Constant]
            | CallInst { callIsTail :: Bool
                       , callConvention :: CallingConvention
                       , callParamAttrs :: [ParamAttribute]
                       , callRetType :: Type
                       , callFunction :: Constant
                       , callArguments :: [(Constant, [ParamAttribute])]
                       , callAttrs :: [FunctionAttribute]
                       , callHasSRet :: Bool
                       }
            | InvokeInst { invokeConvention :: CallingConvention
                         , invokeParamAttrs :: [ParamAttribute]
                         , invokeRetType :: Type
                         , invokeFunction :: Constant
                         , invokeArguments :: [(Constant, [ParamAttribute])]
                         , invokeAttrs :: [FunctionAttribute]
                         , invokeNormalLabel :: Constant
                         , invokeUnwindLabel :: Constant
                         , invokeHasSRet :: Bool
                         }
            | VaArgInst Constant Type
            deriving (Show, Eq)


data Module = Module DataLayout TargetTriple [GlobalDeclaration]
            deriving (Show, Eq)

-- Ident AddrSpace Annotations Type(aptr) Initializer alignment
data GlobalDeclaration = GlobalDeclaration Identifier Int LinkageType GlobalAnnotation Type (Maybe Constant) Integer (Maybe ByteString)
                       | GlobalAlias Identifier LinkageType VisibilityStyle Type Constant
                       | NamedType Identifier Type
                       | ModuleAssembly Assembly
                       | ExternalValueDecl Type Identifier
                       | ExternalFuncDecl Type Identifier [FunctionAttribute]
                       | NamedMetadata Identifier [Constant]
                       | UnnamedMetadata Identifier [Maybe Constant]
                       | FunctionDefinition { funcLinkage :: LinkageType
                                            , funcVisibility :: VisibilityStyle
                                            , funcCC :: CallingConvention
                                            , funcRetAttrs :: [ParamAttribute]
                                            , funcRetType :: Type
                                            , funcName :: Identifier
                                            , funcParams :: [FormalParameter]
                                            , funcAttrs :: [FunctionAttribute]
                                            , funcSection :: Maybe ByteString
                                            , funcAlign :: Integer
                                            , funcGCName :: Maybe GCName
                                            , funcBody :: [BasicBlock]
                                            , funcIsVararg :: Bool
                                            }
                         deriving (Show, Eq)

data FormalParameter = FormalParameter Type [ParamAttribute] Identifier
                     deriving (Show, Eq)

data ConstantT = BlockAddress Identifier Identifier -- Func Ident, Block Label -- to be resolved into something useful later
               | ConstantAggregateZero
               | ConstantArray [Constant] -- This should have some parameters but I don't know what
               | ConstantExpr InstructionT -- change this to something else maybe?  Value should suffice... might even eliminate this one
               | ConstantFP Double
               | ConstantInt Integer
               | ConstantString ByteString
               | ConstantPointerNull
               | ConstantStruct [Constant] -- Just a list of other constants
               | ConstantVector [Constant] -- again
               | UndefValue
               | MDNode [Maybe Constant] -- A list of constants (and other metadata)
               | MDString ByteString
               | GlobalVariable VisibilityStyle LinkageType ByteString
               | InlineAsm ByteString ByteString -- asm, constraints
               deriving (Show, Eq)


data BasicBlock = BasicBlock (Maybe Identifier) [Instruction]
                deriving (Show, Eq)

data Type = TypeInteger Int -- bits
          | TypeFloat
          | TypeDouble
          | TypeFP128
          | TypeX86FP80
          | TypePPCFP128
          | TypeX86MMX
          | TypeVoid
          | TypeLabel
          | TypeMetadata
          | TypeArray Integer Type
          | TypeVector Integer Type
          | TypeFunction Type [Type] Bool -- Return type, arg types, vararg
          | TypeOpaque
          | TypePointer Type -- (Maybe Int) -- Address Space
          | TypeStruct [Type]
          | TypePackedStruct [Type]
          | TypeUpref Int
          | TypeNamed Identifier
          deriving (Show, Eq)

