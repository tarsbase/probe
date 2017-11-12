{-# LANGUAGE OverloadedStrings #-}

module Printing where

import Options

-- https://hackage.haskell.org/package/bytestring
-- https://hackage.haskell.org/package/bytestring-0.10.8.2/docs/Data-ByteString-Lazy.html
import qualified Data.ByteString.Lazy.Char8 as L8
-- https://hackage.haskell.org/package/bytestring-0.10.8.1/docs/Data-ByteString.html
import qualified Data.ByteString as BS
-- https://hackage.haskell.org/package/mtl-2.2.1/docs/Control-Monad-Reader.html
import Control.Monad.Reader
-- http://hackage.haskell.org/package/stm
-- http://hackage.haskell.org/package/stm-2.4.4.1/docs/Control-Concurrent-STM.html
-- http://hackage.haskell.org/package/stm-2.4.4.1/docs/Control-Concurrent-STM-TChan.html
import Control.Concurrent.STM
import System.IO (hFlush, stdout)
-- https://hackage.haskell.org/package/regex-posix
-- https://hackage.haskell.org/package/regex-posix-0.95.2/docs/Text-Regex-Posix.html
-- https://wiki.haskell.org/Regex_Posix
import Text.Regex.Posix
-- http://hackage.haskell.org/package/http-client
-- http://hackage.haskell.org/package/http-client-tls
-- https://github.com/snoyberg/http-client
import Network.HTTP.Simple ( Response )
import Network.HTTP.Client ( responseStatus
                           , responseBody
                           , Manager
                           , httpLbs
                           , newManager
                           , managerSetProxy
                           , noProxy
                           , responseHeaders
                           , cookie_domain
                           , cookie_name
                           , destroyCookieJar
                           , responseCookieJar
                           )

errorPattern :: L8.ByteString
errorPattern = "^ERROR:" :: L8.ByteString

isError :: String -> Bool
isError = flip (=~) errorPattern

printReaderContent :: ReaderT String IO ()
printReaderContent = do
    content <- ask
    liftIO $ putStrLn ("The URL Checker: " ++ content)

-- printOrNot :: (MonadIO m, MonadReader Options m) => String -> m ()
printOrNot :: String -> ReaderT Options IO ()
printOrNot msg = do
    opts <- ask
    when (optVerbose opts) $ liftIO $ putStrLn msg

printBadLinks :: TChan String -> IO ()
printBadLinks c =
  forever $ atomically (readTChan c) >>= (\s -> putStrLn $ "badLink: " ++ s) >> hFlush stdout

printGoodLinks :: TChan String -> IO ()
printGoodLinks c =
  forever $ atomically (readTChan c) >>= (\s -> putStrLn $ "- " ++ s) >> hFlush stdout

-- | printLinksOrgMode
-- Checking if the prefix contains "ERROR:" it's just a matter of checking the
-- first 6 characters (take 6).
printLinksOrgMode :: (Foldable t1) => t3 -> t2 -> t1 String -> Options -> IO ()
printLinksOrgMode _u _r tl o =
    mapM_ pf tl
      where pf :: String -> IO ()
            pf s = if optErrors o
                     then when (isError $ take 6 s) $ putStrLn s
                   else putStrLn s

maybePrintSomething :: (Show a, MonadIO f) => a -> Response body -> Maybe String -> Options -> f ()
maybePrintSomething u r t o =
    when (optVerbose o) (
        maybePrintServer u (getServer r) t >>
            liftIO (maybePrintCookies u r) >>
                maybePrintContentLength (getContentLength r))

-- https://hackage.haskell.org/package/http-client-0.5.7.0/docs/Network-HTTP-Client.html#t:CookieJar
maybePrintCookies :: (Show a) => a -> Response body -> IO ()
maybePrintCookies u r =
    mapM_
    (\c -> putStrLn $ " - "
           ++ show u
           ++ " : cookieName: "
           ++ show (cookie_name c)
           ++ ", cookieDomain; "
           ++ show (cookie_domain c))
    (destroyCookieJar (responseCookieJar r))

serverLine :: (Show a1, Show a2 ) => a1 -> Maybe a2 -> Maybe String -> String
serverLine u m (Just t) =
    case m of
        Just sr -> "[" ++ show u ++ "] with title \"" ++ t ++ "\" is served by " ++ show sr ++ "."
        Nothing -> "[" ++ show u ++ "] with title \"" ++ t ++ "\" is served by an anonymous server"
serverLine u m Nothing =
    case m of
        Just sr -> "[" ++ show u ++ "] is served by " ++ show sr ++ "."
        Nothing -> "[" ++ show u ++ "] is served by an anonymous server"

maybePrintServer :: (Show a, Show b, MonadIO m) => a -> Maybe b -> Maybe String -> m ()
maybePrintServer u m t = liftIO $ putStrLn (serverLine u m t)

contentLengthLine :: Show a => Maybe a -> String
contentLengthLine m =
    case m of
        Just cl -> "Found something: " ++ show cl ++ " (content length)"
        Nothing -> "Found something but without contentLength"

maybePrintContentLength :: (Show a, MonadIO m) => Maybe a -> m ()
maybePrintContentLength = liftIO . putStrLn . contentLengthLine

printURLs :: FilePath -> IO ()
printURLs f = do
    putStrLn ("printURLs from " ++ show f)
    src <- liftIO $ L8.readFile f
    let urls = parseLinks src
    mapM_ (\s -> putStrLn $ " - " ++ show s) urls
