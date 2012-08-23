module Hans.Layer.Tcp.Messages where

import Hans.Layer.Tcp.Monad
import Hans.Layer.Tcp.Types
import Hans.Layer.Tcp.Window
import Hans.Message.Tcp

import qualified Data.ByteString.Lazy as L


-- Generic Packets -------------------------------------------------------------

mkSegment :: TcpSocket -> TcpHeader
mkSegment tcp = emptyTcpHeader
  { tcpDestPort   = sidRemotePort (tcpSocketId tcp)
  , tcpSourcePort = sidLocalPort (tcpSocketId tcp)
  , tcpSeqNum     = tcpSndNxt tcp
  , tcpAckNum     = tcpRcvNxt tcp
    -- XXX this doesn't really reflect the right number
  , tcpWindow     = fromIntegral (availableBytes (tcpInBuffer tcp))
  }

mkAck :: TcpSocket -> TcpHeader
mkAck tcp = (mkSegment tcp)
  { tcpAck = True
  }


-- Connection Refusal ----------------------------------------------------------

-- | Given a tcp header, generate the next header in the sequence that
-- corresponds to the RST ACK response.
mkRstAck :: TcpHeader -> TcpHeader
mkRstAck hdr = emptyTcpHeader
  -- XXX need a story for what to set the SN to here
  { tcpSeqNum     = 0
  , tcpAckNum     = tcpSeqNum hdr + 1
  , tcpSourcePort = tcpDestPort hdr
  , tcpDestPort   = tcpSourcePort hdr
  , tcpAck        = True
  , tcpRst        = True
  }


-- Connection Establishment ----------------------------------------------------

mkSyn :: TcpSocket -> TcpHeader
mkSyn tcp
  = setTcpOption (OptMaxSegmentSize (fromIntegral (tcpInMSS tcp)))
  $ (mkSegment tcp)
    { tcpSyn    = True
    , tcpAckNum = 0
    }

-- | Construct a SYN ACK packet, in response to a SYN.
mkSynAck :: TcpSocket -> TcpHeader
mkSynAck tcp
  = setTcpOption (OptMaxSegmentSize (fromIntegral (tcpInMSS tcp)))
  $ (mkSegment tcp)
    { tcpSyn = True
    , tcpAck = True
    }


-- Connection Closing ----------------------------------------------------------

-- | Construct a FIN packet.
mkFinAck :: TcpSocket -> TcpHeader
mkFinAck tcp = (mkSegment tcp)
  { tcpFin = True
  , tcpAck = True
  }


-- Data Packets ----------------------------------------------------------------

mkData :: TcpSocket -> TcpHeader
mkData tcp = (mkSegment tcp)
  { tcpAck = True
  , tcpPsh = True
  }


-- Socket Actions --------------------------------------------------------------

syn :: Sock ()
syn  = do
  tcp <- getTcpSocket
  tcpOutput (mkSyn tcp) L.empty
  advanceSndNxt 1

-- | Respond to a SYN message with a SYN ACK message.
synAck :: Sock ()
synAck  = do
  advanceRcvNxt 1
  tcp <- getTcpSocket
  tcpOutput (mkSynAck tcp) L.empty
  advanceSndNxt 1

-- | Send an ACK packet.
ack :: Sock ()
ack  = do
  clearDelayedAck
  tcp <- getTcpSocket
  tcpOutput (mkAck tcp) L.empty

-- | Schedule a delayed ACK packet.
delayedAck :: Sock ()
delayedAck  = modifyTcpTimers_ (\tt -> tt { ttDelayedAck = True })

-- | Unschedule a delayed ACK packet.
clearDelayedAck :: Sock ()
clearDelayedAck  = modifyTcpTimers_ (\tt -> tt { ttDelayedAck = False })

-- | Send a FIN packet to begin closing a connection.
finAck :: Sock ()
finAck  = do
  tcp <- getTcpSocket
  tcpOutput (mkFinAck tcp) L.empty
  advanceSndNxt 1
  clearDelayedAck

-- | Send a segment.
outputSegment :: OutSegment -> Sock ()
outputSegment seg = do
  clearDelayedAck
  tcpOutput (outHeader seg) (outBody seg)


-- Flag Tests ------------------------------------------------------------------

isSyn :: TcpHeader -> Bool
isSyn hdr = foldr step (tcpSyn hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpAck, tcpPsh, tcpRst, tcpFin ]

isSynAck :: TcpHeader -> Bool
isSynAck hdr = foldr step (tcpSyn hdr && tcpAck hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpPsh, tcpRst, tcpFin ]

isRstAck :: TcpHeader -> Bool
isRstAck hdr = foldr step (tcpRst hdr && tcpAck hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpPsh, tcpSyn, tcpFin ]

isAck :: TcpHeader -> Bool
isAck hdr = foldr step (tcpAck hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpPsh, tcpRst, tcpSyn, tcpFin ]

isFin :: TcpHeader -> Bool
isFin hdr = foldr step (tcpFin hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpAck, tcpPsh, tcpRst, tcpSyn ]

isFinAck :: TcpHeader -> Bool
isFinAck hdr = foldr step (tcpFin hdr && tcpAck hdr) fields
  where
  step p r = r && not (p hdr)
  fields   = [ tcpCwr, tcpEce, tcpUrg, tcpPsh, tcpRst, tcpSyn ]
