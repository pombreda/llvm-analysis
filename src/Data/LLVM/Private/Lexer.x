{
{-# LANGUAGE RankNTypes, OverloadedStrings #-}
module Data.LLVM.Private.Lexer ( lexer, LexerToken(..), Token, AlexPosn(..) ) where

import Data.Binary.IEEE754
import Data.Char (digitToInt)
import Data.Monoid
import Data.Text (Text)
import qualified Data.Text as T
}

$digit = 0-9
$hexdigit = [$digit a-f A-F]
$alpha = [a-zA-Z]
$startChar = [$alpha \$ \. \_]
$identChar = [$startChar $digit \-]
$whitespace = [\ \t\b\n]
$labelChar = [$identChar \-]
-- LLVM String characters are simple - quotes are represented as \22
-- (an ascii escape) so parsing them is simple
$stringChar = [^\"]

@decimal = [$digit]+
@quotedString = \" $stringChar* \"

tokens :-
  "," $whitespace* "!dbg" { simpleTok TDbg }
  -- Identifiers
  "@" $startChar $identChar* { mkGlobalIdent }
  "%" $startChar $identChar* { mkLocalIdent }
  "!" $startChar $identChar* { mkMetadataName }
  -- Unnamed identifiers
  "@" @decimal+ { mkGlobalIdent }
  "%" @decimal+ { mkLocalIdent }
  "!" @decimal+ { mkMetadataName }
  -- Quoted string idents
  "@" @quotedString { mkQGlobalIdent }
  "%" @quotedString { mkQLocalIdent }

  -- Labels
  -- Drop the trailing : char
  $labelChar+ ":" { stringTok TLabel T.init }
  -- There is an alternate form that seems to be much more common
  -- in the assembly generated by llvm-dis/opt:
  --
  --  ; <label>:###
  -- That is, a label encoded as a comment
  "; <label>:" @decimal .* { mkAnonLabel }
  -- Normal comment
  ";" .* ;

  -- Standard literals
  "-"? @decimal { mkIntLit }
  "-"? @decimal "." @decimal ("e" [\+\-]? @decimal)? { mkFloatLit }
  "0x"  $hexdigit+ { mkHexFloatLit 2 }
  "0xK" $hexdigit+ { mkHexFloatLit 3 }
  "0xM" $hexdigit+ { mkHexFloatLit 3 }
  "0xL" $hexdigit+ { mkHexFloatLit 3 }
  "c" @quotedString { mkStringConstant }
  "!" @quotedString { mkMetadataString }
  "true"  { simpleTok TTrueLit }
  "false" { simpleTok TFalseLit }
  "null"  { simpleTok TNullLit }
  "undef" { simpleTok TUndefLit }
  "zeroinitializer" { simpleTok TZeroInitializer }
  @quotedString { stringTok TString unquote }


  -- Operator-like things
  ","   { simpleTok TComma }
  "="   { simpleTok TAssign }
  "*"   { simpleTok TStar }
  "("   { simpleTok TLParen }
  ")"   { simpleTok TRParen }
  "["   { simpleTok TLSquare }
  "]"   { simpleTok TRSquare }
  "{"   { simpleTok TLCurl }
  "}"   { simpleTok TRCurl }
  "<"   { simpleTok TLAngle }
  ">"   { simpleTok TRAngle }
  "!"   { simpleTok TBang }
  "x"   { simpleTok TAggLen }
  "to"  { simpleTok TTo }
  "..." { simpleTok TDotDotDot }

  -- Linkage Types
  "private"   { simpleTok TPrivate }
  "linker_private" { simpleTok TLinkerPrivate }
  "linker_private_weak" { simpleTok TLinkerPrivateWeak }
  "linker_private_weak_def_auto" { simpleTok TLinkerPrivateWeakDefAuto }
  "internal"  { simpleTok TInternal }
  "available_externally" { simpleTok TAvailableExternally }
  "linkonce"  { simpleTok TLinkOnce }
  "weak"      { simpleTok TWeak }
  "common"    { simpleTok TCommon }
  "appending" { simpleTok TAppending }
  "extern_weak" { simpleTok TExternWeak }
  "linkonce_odr" { simpleTok TLinkOnceODR }
  "weak_odr"  { simpleTok TWeakODR }
  "dllimport" { simpleTok TDLLImport }
  "dllexport" { simpleTok TDLLExport }
  "external"  { simpleTok TExternal }

  -- Calling Conventions
  "ccc"    { simpleTok TCCCCC }
  "fastcc" { simpleTok TCCFastCC }
  "coldcc" { simpleTok TCCColdCC }
  "cc 10"  { simpleTok TCCGHC }
  "cc " @decimal { mkNumberedCC }

  -- Visibility styles
  "default"   { simpleTok TVisDefault }
  "hidden"    { simpleTok TVisHidden }
  "protected" { simpleTok TVisProtected }

  -- Parameter Attributes
  "zeroext"   { simpleTok TPAZeroExt }
  "signext"   { simpleTok TPASignExt }
  "inreg"     { simpleTok TPAInReg }
  "byval"     { simpleTok TPAByVal }
  "sret"      { simpleTok TPASRet }
  "noalias"   { simpleTok TPANoAlias }
  "nocapture" { simpleTok TPANoCapture }
  "nest"      { simpleTok TPANest }

  -- Function Attributes
  "alignstack(" @decimal ")" { mkAlignStack }
  "alwaysinline"    { simpleTok TFAAlwaysInline }
  "hotpatch"        { simpleTok TFAHotPatch }
  "inlinehint"      { simpleTok TFAInlineHint }
  "naked"           { simpleTok TFANaked }
  "noimplicitfloat" { simpleTok TFANoImplicitFloat }
  "noinline"        { simpleTok TFANoInline }
  "noredzone"       { simpleTok TFANoRedZone }
  "noreturn"        { simpleTok TFANoReturn }
  "nounwind"        { simpleTok TFANoUnwind }
  "optsize"         { simpleTok TFAOptSize }
  "readnone"        { simpleTok TFAReadNone }
  "readonly"        { simpleTok TFAReadOnly }
  "ssp"             { simpleTok TFASSP }
  "sspreq"          { simpleTok TFASSPReq }

  -- Types
  "i" @decimal { mkIntegralType }
  "float"      { simpleTok TFloatT }
  "double"     { simpleTok TDoubleT }
  "x86_fp80"   { simpleTok TX86_FP80T }
  "fp128"      { simpleTok TFP128T }
  "ppc_fp128"  { simpleTok TPPC_FP128T }
  "x86mmx"     { simpleTok TX86mmxT }
  "void"       { simpleTok TVoidT }
  "metadata"   { simpleTok TMetadataT }
  "opaque"     { simpleTok TOpaqueT }
  "label"      { simpleTok TLabelT }
  "\\" @decimal  { mkTypeUpref }


  -- Keyword-like things
  "addrspace(" @decimal ")" { mkAddrSpace }
  "type"       { simpleTok TType }
  "constant"   { simpleTok TConstant }
  "section"    { simpleTok TSection }
  "align" $whitespace+ @decimal { mkAlign }
  "alignstack" { simpleTok TAlignStack }
  "sideeffect" { simpleTok TSideEffect }
  "alias"      { simpleTok TAlias }
  "declare"    { simpleTok TDeclare }
  "define"     { simpleTok TDefine }
  "gc"         { simpleTok TGC }
  "module"     { simpleTok TModule }
  "asm"        { simpleTok TAsm }
  "target"     { simpleTok TTarget }
  "datalayout" { simpleTok TDataLayout }
  "blockaddress" { simpleTok TBlockAddress }
  "inbounds"   { simpleTok TInbounds }
  "global"     { simpleTok TGlobal }
  "appending"  { simpleTok TAppending }
  "nuw"        { simpleTok TNUW }
  "nsw"        { simpleTok TNSW }
  "exact"      { simpleTok TExact }
  "volatile"   { simpleTok TVolatile }
  "tail"       { simpleTok TTail }
  "triple"     { simpleTok TTriple }
  "external"   { simpleTok TExternal }

  -- Instructions
  "trunc"          { simpleTok TTrunc }
  "zext"           { simpleTok TZext }
  "sext"           { simpleTok TSext }
  "fptrunc"        { simpleTok TFpTrunc }
  "fpext"          { simpleTok TFpExt }
  "fptoui"         { simpleTok TFpToUI }
  "fptosi"         { simpleTok TFpToSI }
  "uitofp"         { simpleTok TUIToFp }
  "sitofp"         { simpleTok TSIToFp }
  "ptrtoint"       { simpleTok TPtrToInt }
  "inttoptr"       { simpleTok TIntToPtr }
  "bitcast"        { simpleTok TBitCast }
  "getelementptr"  { simpleTok TGetElementPtr }
  "select"         { simpleTok TSelect }
  "icmp"           { simpleTok TIcmp }
  "fcmp"           { simpleTok TFcmp }
  "extractelement" { simpleTok TExtractElement }
  "insertelement"  { simpleTok TInsertElement }
  "shufflevector"  { simpleTok TShuffleVector }
  "extractvalue"   { simpleTok TExtractValue }
  "insertvalue"    { simpleTok TInsertValue }
  "call"           { simpleTok TCall }
  "ret"            { simpleTok TRet }
  "br"             { simpleTok TBr }
  "switch"         { simpleTok TSwitch }
  "indirectbr"     { simpleTok TIndirectBr }
  "invoke"         { simpleTok TInvoke }
  "unwind"         { simpleTok TUnwind }
  "unreachable"    { simpleTok TUnreachable }
  "add"            { simpleTok TAdd }
  "fadd"           { simpleTok TFadd }
  "sub"            { simpleTok TSub }
  "fsub"           { simpleTok TFsub }
  "mul"            { simpleTok TMul }
  "fmul"           { simpleTok TFmul }
  "udiv"           { simpleTok TUdiv }
  "sdiv"           { simpleTok TSdiv }
  "fdiv"           { simpleTok TFdiv }
  "urem"           { simpleTok TUrem }
  "srem"           { simpleTok TSrem }
  "frem"           { simpleTok TFrem }
  "shl"            { simpleTok TShl }
  "lshr"           { simpleTok TLshr }
  "ashr"           { simpleTok TAshr }
  "and"            { simpleTok TAnd }
  "or"             { simpleTok TOr }
  "xor"            { simpleTok TXor }
  "alloca"         { simpleTok TAlloca }
  "load"           { simpleTok TLoad }
  "store"          { simpleTok TStore }
  "phi"            { simpleTok TPhi }
  "va_arg"         { simpleTok TVaArg }

-- cmp styles
  "eq"             { simpleTok Teq }
  "ne"             { simpleTok Tne }
  "ugt"            { simpleTok Tugt }
  "uge"            { simpleTok Tuge }
  "ult"            { simpleTok Tult }
  "ule"            { simpleTok Tule }
  "sgt"            { simpleTok Tsgt }
  "sge"            { simpleTok Tsge }
  "slt"            { simpleTok Tslt }
  "sle"            { simpleTok Tsle }
  "oeq"            { simpleTok Toeq }
  "ogt"            { simpleTok Togt }
  "oge"            { simpleTok Toge }
  "olt"            { simpleTok Tolt }
  "ole"            { simpleTok Tole }
  "one"            { simpleTok Tone }
  "ord"            { simpleTok Tord }
  "ueq"            { simpleTok Tueq }
  "une"            { simpleTok Tune }
  "uno"            { simpleTok Tuno }

  $whitespace+ ;

{
data LexerToken = TIntLit Integer
           | TFloatLit !Double
           | TStringLit !Text
           | TMetadataString !Text
           | TTrueLit
           | TFalseLit
           | TNullLit
           | TUndefLit
           | TZeroInitializer
           | TString !Text
           | TLabel !Text

           -- Operator-like tokens
           | TComma
           | TAssign
           | TStar
           | TLParen
           | TRParen
           | TLSquare
           | TRSquare
           | TLCurl
           | TRCurl
           | TLAngle
           | TRAngle
           | TBang
           | TAggLen
           | TTo
           | TDotDotDot

           -- Identifiers
           | TLocalIdent Text
           | TGlobalIdent Text
           | TMetadataName Text

           -- Linkage Types
           | TPrivate
           | TLinkerPrivate
           | TLinkerPrivateWeak
           | TLinkerPrivateWeakDefAuto
           | TInternal
           | TAvailableExternally
           | TLinkOnce
           | TWeak
           | TCommon
           | TAppending
           | TExternWeak
           | TLinkOnceODR
           | TWeakODR
           | TDLLImport
           | TDLLExport

           -- Calling Conventions
           | TCCCCC
           | TCCFastCC
           | TCCColdCC
           | TCCGHC
           | TCCN !Int

           -- Visibility Style
           | TVisDefault
           | TVisHidden
           | TVisProtected

           -- Param Attributes
           | TPAZeroExt
           | TPASignExt
           | TPAInReg
           | TPAByVal
           | TPASRet
           | TPANoAlias
           | TPANoCapture
           | TPANest

           -- Function Attributes
           | TFAAlignStack !Int
           | TFAAlwaysInline
           | TFAHotPatch
           | TFAInlineHint
           | TFANaked
           | TFANoImplicitFloat
           | TFANoInline
           | TFANoRedZone
           | TFANoReturn
           | TFANoUnwind
           | TFAOptSize
           | TFAReadNone
           | TFAReadOnly
           | TFASSP
           | TFASSPReq

           -- Types
           | TIntegralT !Int -- bitsize
           | TFloatT
           | TDoubleT
           | TX86_FP80T
           | TFP128T
           | TPPC_FP128T
           | TX86mmxT
           | TVoidT
           | TMetadataT
           | TOpaqueT
           | TUprefT !Int
           | TLabelT

           -- Keywords
           | TType
           | TAddrspace !Int
           | TConstant
           | TSection
           | TAlign !Int
           | TAlignStack
           | TSideEffect
           | TAlias
           | TDeclare
           | TDefine
           | TGC
           | TModule
           | TAsm
           | TTarget
           | TDataLayout
           | TBlockAddress
           | TInbounds
           | TGlobal
           | TTail
           | TTriple
           | TDbg
           | TExternal

           -- Add modifiers
           | TNUW
           | TNSW

           -- Div mods
           | TExact

           -- Load/Store mods
           | TVolatile

           -- Instructions
           | TTrunc
           | TZext
           | TSext
           | TFpTrunc
           | TFpExt
           | TFpToUI
           | TFpToSI
           | TUIToFp
           | TSIToFp
           | TPtrToInt
           | TIntToPtr
           | TBitCast
           | TGetElementPtr
           | TSelect
           | TIcmp
           | TFcmp
           | TExtractElement
           | TInsertElement
           | TShuffleVector
           | TExtractValue
           | TInsertValue
           | TCall
           | TRet
           | TBr
           | TSwitch
           | TIndirectBr
           | TInvoke
           | TUnwind
           | TUnreachable
           | TAdd
           | TFadd
           | TSub
           | TFsub
           | TMul
           | TFmul
           | TUdiv
           | TSdiv
           | TFdiv
           | TUrem
           | TSrem
           | TFrem
           | TShl
           | TLshr
           | TAshr
           | TAnd
           | TOr
           | TXor
           | TAlloca
           | TLoad
           | TStore
           | TPhi
           | TVaArg
           -- cmp styles
           | Teq
           | Tne
           | Tugt
           | Tuge
           | Tult
           | Tule
           | Tsgt
           | Tsge
           | Tslt
           | Tsle
           | Toeq
           | Togt
           | Toge
           | Tolt
           | Tole
           | Tone
           | Tord
           | Tueq
           | Tune
           | Tuno
         deriving (Show, Eq)

type Token = (AlexPosn, LexerToken)

simpleTok :: LexerToken -> AlexPosn -> Text -> Token
simpleTok t pos _ = (pos, t)

stringTok :: (Text -> LexerToken) -> (Text -> Text) ->
             AlexPosn -> Text -> Token
stringTok t fltr pos s = (pos, t (fltr s))

-- Helpers for constructing identifiers
mkGlobalIdent = stringTok TGlobalIdent stripSigil
mkLocalIdent = stringTok TLocalIdent stripSigil
mkMetadataName = stringTok TMetadataName stripSigil
mkQGlobalIdent = stringTok TGlobalIdent (unquote . stripSigil)
mkQLocalIdent = stringTok TLocalIdent (unquote . stripSigil)
mkQMetadataName = stringTok TMetadataName (unquote . stripSigil)
stripSigil = T.tail
unquote = T.tail . T.init

-- First, drop the comment prefix.  The label name is all of the
-- digits following that.  The rest of the line is garbage.
mkAnonLabel = stringTok TLabel (T.takeWhile isDigit . T.drop 10)
  where isDigit c = c >= '0' && c <= '9'

-- Helpers for the simple literals
mkIntLit pos s = (pos, TIntLit $ fromIntegral $ readTextInt s)
mkFloatLit pos s = (pos, TFloatLit $ readText s)
-- Drop the first pfxLen characters (0x)
mkHexFloatLit pfxLen pos s = (pos, TFloatLit $ wordToDouble $ readText s')
  where s' = "0x" `mappend` (T.drop pfxLen s)
-- Strip off the leading c and then unquote
mkStringConstant = stringTok TStringLit (unquote . T.tail)
mkMetadataString = stringTok TMetadataString (unquote . T.tail)

readText :: (Read a) => Text -> a
readText = read . T.unpack

readTextInt :: Text -> Int
readTextInt t = fst $ T.foldr f (0, 0) t
  where f '-' (acc, _) = (-acc, -1)
        f c (acc, idx) | idx /= -1 = (acc + (digitToInt c) * (10 ^ idx), idx+1)
                       | otherwise = error "Not a number"

-- Discard "cc "
mkNumberedCC pos s = (pos, TCCN $ readTextInt $ T.drop 3 s)

-- Extract part between parens (TFAAlignStack Int)
mkAlignStack pos s = (pos, TFAAlignStack $ readText s')
  where s' = T.drop 11 $ T.init s

mkAlign pos s = (pos, TAlign $ readTextInt s')
  where s' = T.dropWhile (\x -> x == ' ' || x == '\t') $ T.drop 5 s

-- Types
mkTypeUpref pos s = (pos, TUprefT $ readTextInt $ T.tail s)
mkIntegralType pos s = (pos, TIntegralT $ readTextInt $ T.tail s)

mkAddrSpace pos s = (pos, TAddrspace $ readText s')
  where s' = T.drop 10 $ T.init s

-- Exported interface
lexer = alexScanTokens




-- This is a Text-posn wrapper, derived from posn-bytestring

data AlexPosn = AlexPn !Int !Int !Int
     deriving (Eq, Show)
type AlexInput = (AlexPosn, Char, Text)

alexGetChar :: AlexInput -> Maybe (Char, AlexInput)
-- alexGetChar :: forall t . (t, Text) -> Maybe (Char, (Char, Text))
alexGetChar (p,_,cs) | T.null cs = Nothing
                     | otherwise = let c   = T.head cs
                                       cs' = T.tail cs
                                       p'  = alexMove p c
                                    in p' `seq` cs' `seq` Just (c, (p', c, cs'))
-- Just (T.head cs, (T.head cs, T.tail cs))

alexInputPrevChar :: forall t t1 t2 . (t, t1, t2) -> t1
alexInputPrevChar (_,c,_) = c

alexStartPos :: AlexPosn
alexStartPos = AlexPn 0 1 1

alexMove :: AlexPosn -> Char -> AlexPosn
alexMove (AlexPn a l c) '\t' = AlexPn (a+1) l     (((c+7) `div` 8) * 8 + 1)
alexMove (AlexPn a l c) '\n' = AlexPn (a+1) (l+1) 1
alexMove (AlexPn a l c) _ =    AlexPn (a+1) l     (c+1)

alexScanTokens :: Text -> [Token]
alexScanTokens str = go (alexStartPos, '\n', str)
  where go inp@(pos,_, str) =
          case alexScan inp 0 of
            AlexEOF -> []
            AlexError ((AlexPn _ line col), _, _) -> error $ "lexical error at line " ++ (show line) ++ ", column " ++ (show col)
            AlexSkip inp' _ -> go inp'
            AlexToken inp' len act -> act pos (T.take (fromIntegral len) str) : go inp'


}