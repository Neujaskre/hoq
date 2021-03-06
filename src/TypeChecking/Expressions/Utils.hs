module TypeChecking.Expressions.Utils where

import Data.Bifunctor
import Data.Void

import Syntax
import Syntax.ErrorDoc
import Syntax.PrettyPrinter
import Semantics
import Semantics.Value
import TypeChecking.Context
import TypeChecking.Monad.Warn

data Error = Error { errorType :: ErrorType, errorMsg :: EMsg (Term Syntax) }
    deriving Show

instance Eq Error where
    Error e _ == Error e' _ = e == e'

data ErrorType
    = NotInScope
    | Inference
    | TooManyArgs
    | NotEnoughArgs
    | Coverage
    | TypeMismatch
    | Conditions
    | Other
    deriving (Eq, Show)

data Argument = Argument Int Posn (Maybe Name) | NoArgument Int [Error]
    deriving Show

argumentIndex :: Argument -> Int
argumentIndex (Argument k _ _) = k
argumentIndex (NoArgument k _) = k

instance Eq Argument where
    arg == arg' = argumentIndex arg == argumentIndex arg'

notInScope :: Show a => Posn -> String -> a -> Error
notInScope pos s a = Error NotInScope $ emsgLC pos ("Not in scope: " ++ (if null s then "" else s ++ " ") ++ show a) enull

inferErrorMsg :: Posn -> String -> Error
inferErrorMsg pos s = Error Inference $ emsgLC pos ("Cannot infer type of " ++ s) enull

inferExprErrorMsg :: Posn -> Error
inferExprErrorMsg pos = Error Inference $ emsgLC pos "Cannot infer an expressions" enull

inferArgErrorMsg :: Argument -> [Error]
inferArgErrorMsg (Argument k pos mname) = [Error Inference $ emsgLC pos
    ("Cannot infer " ++ nth (k + 1) ++ " argument" ++ maybe "" (\name -> " for " ++ nameToPrefix name) mname) enull]
  where
    nth 1 = "first"
    nth 2 = "second"
    nth 3 = "third"
    nth n = show n ++ "th"
inferArgErrorMsg (NoArgument _ errs) = errs

inferParamsErrorMsg :: Show a => Posn -> a -> Error
inferParamsErrorMsg pos d = Error Inference $ emsgLC pos ("Cannot infer parameters of data constructor " ++ show d) enull

argsErrorMsg :: Posn -> String -> Error
argsErrorMsg pos s = Error TooManyArgs $ emsgLC pos (s ++ " is applied to arguments") enull

expectedArgErrorMsg :: Show a => Posn -> a -> Error
expectedArgErrorMsg lc d = Error NotEnoughArgs $ emsgLC lc ("Expected an argument to " ++ show d) enull

coverageErrorMsg :: Posn -> Maybe [Posn] -> [Error]
coverageErrorMsg pos Nothing = [Error Coverage $ emsgLC pos "Incomplete pattern matching" enull]
coverageErrorMsg _ (Just uc) = map (\pos -> Error Coverage $ emsgLC pos "Unreachable clause" enull) uc

notEnoughArgs :: Show a => Posn -> a -> Error
notEnoughArgs pos a = Error NotEnoughArgs $ emsgLC pos ("Not enough arguments to " ++ show a) enull

tooManyArgs :: Posn -> Error
tooManyArgs pos = Error TooManyArgs $ emsgLC pos "Too many arguments" enull

conditionsErrorMsg :: Posn -> Ctx String f Void a -> ([String], Term Semantics a, Term Semantics a, Term Semantics a) -> Error
conditionsErrorMsg pos ctx (vs, t1, t2, t3) = Error Conditions $ emsgLC pos "Conditions check failed:"
    $  scopeToEDoc ctx vs t1 <+> pretty "equals to" <+> scopeToEDoc ctx vs t2
    $$ pretty "but should be equal to" <+> scopeToEDoc ctx vs t3
  where
    scopeToEDoc :: Ctx String f Void a -> [String] -> Term Semantics a -> EDoc (Term Syntax)
    scopeToEDoc ctx vs t = epretty $ bimap syntax pretty $ apps (vacuous $ abstractTerm ctx t) $ map cvar (ctxVars ctx ++ vs)

prettyOpen :: Ctx String (Type Semantics) Void a -> Term Semantics a -> EDoc (Term Syntax)
prettyOpen ctx term = epretty $ fmap (pretty . either id absurd) $ close ctx (bimap syntax Right term)

checkIsType :: Monad m => Ctx String (Type Semantics) Void a -> Posn -> Term Semantics a -> WarnT [Error] m Sort
checkIsType _ _ (Apply (Semantics _ (Universe k)) _) = return k
checkIsType ctx pos t = throwError [Error TypeMismatch $ emsgLC pos "" $ pretty "Expected type: Type"
                                                                      $$ pretty "Actual type:" <+> prettyOpen ctx t]

termPos :: Term (Posn, s) a -> Posn
termPos (Apply (pos, _) _) = pos
termPos _ = error "termPos"

catchErrorType :: Monad m => [ErrorType] -> WarnT [Error] m a -> ([Error] -> WarnT [Error] m a) -> WarnT [Error] m a
catchErrorType errs = catchErrorBy $ \(Error err _) -> err `elem` errs
