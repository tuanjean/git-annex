{- git-annex output messages
 -
 - Copyright 2010-2011 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Messages (
	showStart,
	showNote,
	showAction,
	showProgress,
	metered,
	MeterUpdate,
	showSideAction,
	showOutput,
	showLongNote,
	showEndOk,
	showEndFail,
	showEndResult,
	showErr,
	warning,
	indent,
	maybeShowJSON,
	showFullJSON,
	showCustom,
	showHeader,
	showRaw,
	
	setupConsole
) where

import Text.JSON
import Data.Progress.Meter
import Data.Progress.Tracker
import Data.Quantity

import Common
import Types
import Types.Key
import qualified Annex
import qualified Messages.JSON as JSON

showStart :: String -> String -> Annex ()
showStart command file = handle (JSON.start command $ Just file) $
	flushed $ putStr $ command ++ " " ++ file ++ " "

showNote :: String -> Annex ()
showNote s = handle (JSON.note s) $
	flushed $ putStr $ "(" ++ s ++ ") "

showAction :: String -> Annex ()
showAction s = showNote $ s ++ "..."

{- Progress dots. -}
showProgress :: Annex ()
showProgress = handle q $
	flushed $ putStr "."

{- Shows a progress meter while performing a transfer of a key.
 - The action is passed a callback to use to update the meter. -}
type MeterUpdate = Integer -> IO ()
metered :: Key -> (MeterUpdate -> Annex a) -> Annex a
metered key a = Annex.getState Annex.output >>= go (keySize key)
	where
		go (Just size) Annex.NormalOutput = do
			progress <- liftIO $ newProgress "" size
			meter <- liftIO $ newMeter progress "B" 25 (renderNums binaryOpts 1)
			showOutput
			liftIO $ displayMeter stdout meter
			r <- a $ \n -> liftIO $ do
				incrP progress n
				displayMeter stdout meter
			liftIO $ clearMeter stdout meter
			return r	
                go _ _ = a (const $ return ())

showSideAction :: String -> Annex ()
showSideAction s = handle q $
	putStrLn $ "(" ++ s ++ "...)"

showOutput :: Annex ()
showOutput = handle q $
	putStr "\n"

showLongNote :: String -> Annex ()
showLongNote s = handle (JSON.note s) $
	putStrLn $ '\n' : indent s

showEndOk :: Annex ()
showEndOk = showEndResult True

showEndFail :: Annex ()
showEndFail = showEndResult False

showEndResult :: Bool -> Annex ()
showEndResult ok = handle (JSON.end ok) $ putStrLn msg
	where
		msg
			| ok = "ok"
			| otherwise = "failed"

showErr :: (Show a) => a -> Annex ()
showErr e = warning' $ "git-annex: " ++ show e

warning :: String -> Annex ()
warning = warning' . indent

warning' :: String -> Annex ()
warning' w = do
	handle q $ putStr "\n"
	liftIO $ do
		hFlush stdout
		hPutStrLn stderr w

indent :: String -> String
indent = join "\n" . map (\l -> "  " ++ l) . lines

{- Shows a JSON fragment only when in json mode. -}
maybeShowJSON :: JSON a => [(String, a)] -> Annex ()
maybeShowJSON v = handle (JSON.add v) q

{- Shows a complete JSON value, only when in json mode. -}
showFullJSON :: JSON a => [(String, a)] -> Annex Bool
showFullJSON v = Annex.getState Annex.output >>= liftIO . go
	where
		go Annex.JSONOutput = JSON.complete v >> return True
		go _ = return False

{- Performs an action that outputs nonstandard/customized output, and
 - in JSON mode wraps its output in JSON.start and JSON.end, so it's
 - a complete JSON document.
 - This is only needed when showStart and showEndOk is not used. -}
showCustom :: String -> Annex Bool -> Annex ()
showCustom command a = do
	handle (JSON.start command Nothing) q
	r <- a
	handle (JSON.end r) q

showHeader :: String -> Annex ()
showHeader h = handle q $
	flushed $ putStr $ h ++ ": "

showRaw :: String -> Annex ()
showRaw s = handle q $ putStrLn s

{- This avoids ghc's output layer crashing on invalid encoded characters in
 - filenames when printing them out.
 -}
setupConsole :: IO ()
setupConsole = do
	fileEncoding stdout
	fileEncoding stderr

handle :: IO () -> IO () -> Annex ()
handle json normal = Annex.getState Annex.output >>= go
	where
		go Annex.NormalOutput = liftIO normal
		go Annex.QuietOutput = q
		go Annex.JSONOutput = liftIO $ flushed json

q :: Monad m => m ()
q = return ()

flushed :: IO () -> IO ()
flushed a = a >> hFlush stdout
