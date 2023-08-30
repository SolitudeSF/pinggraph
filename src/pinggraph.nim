import std/[terminal, os, strutils, times, colors, net, nativesockets, monotimes]
import std/posix except SOCK_RAW, IPPROTO_ICMP
import pkg/cligen

type
  TimestampKind = enum
    tkFull = "full", tkShort = "short", tkNone = "none"
  StyleKind = enum
    skBar = "bar", skBlock = "block", skLine = "line", skAscii = "ascii"
  ColorKind = enum
    ck16Color = "16color", ckTruecolor = "truecolor", ckNone = "none"

  IcmpHeaderInner {.union.} = object
    echo: tuple[id, sequence: uint16]
    gateway: uint32
    frag: tuple[unused, mtu: uint16]
    reserved: array[4, uint8]

  IcmpHeader = object
    `type`, code: uint8
    checksum: uint16
    un: IcmpHeaderInner

  PingPacket = object
    header: IcmpHeader
    msg: array[64 - sizeof IcmpHeader, char]

const
  shortTimeFormat = initTimeFormat("HH:mm:ss")
  fullTimeFormat = initTimeFormat("yyyy-MM-dd HH:mm:ss")
  timestampPad = [tkFull: 32, tkShort: 21, tkNone: 12]

  SOL_IP = 0
  IP_TTL = 2
  SO_RCVTIMEO = 20
  ICMP_ECHO = 8

proc checksum(buffer: pointer, len: int): uint16 =
  let buf = cast[ptr UncheckedArray[uint16]](buffer)
  var sum: uint32

  for i in 0..len div 2:
    sum += buf[i]

  if len mod 2 == 1:
    sum += cast[ptr UncheckedArray[uint8]](buffer)[len - 1]

  sum = (sum shr 16) + (sum and 0xFFFF)
  sum += (sum shr 16)
  result = sum.not.uint16

template checksum[T](t: T): uint16 = checksum(addr t, sizeof T)

proc init(t: typedesc[PingPacket], sequence = 0'u16): PingPacket =
  for i in 1..result.msg.high:
    result.msg[i] = chr(i + '0'.ord)
  result.header.`type` = ICMP_ECHO
  result.header.un.echo.id = getCurrentProcessId().uint16
  result.header.un.echo.sequence = sequence
  result.header.checksum = checksum(result)

var looping = true
proc stop {.noconv.} = looping = false

proc pinggraph(
    host: seq[string],
    interval = 0.5,
    max_ping = 300'u,
    count = 0'u,
    style = skBlock,
    no_header = false,
    color = (if (enableTrueColors(); isTrueColorSupported()): ckTruecolor else: ck16Color),
    timestamp = tkNone,
    saturation = 160'u8
  ) =

  if host.len == 0:
    stderr.writeLine "Provide host to ping"
    quit 1
  elif host.len > 1:
    stderr.writeLine "Ignoring additional hosts"

  let
    host = host[0]
    ipAddr = host.getHostByName.addrList[0]
    reverseHost = ipAddr.getHostByAddr.name
    wait = int64(interval * 1000)
    desaturation = 255'u8 - saturation
    colorCoeff = 512.0 - desaturation.float * 2.0
    leftPad = timestampPad[timestamp]
    (sepChar, barChar, halfChars) = case style
      of skBar:
        ("▏", "▄", @["▖"])
      of skBlock:
        ("▏", "█", @["▏","▎","▍","▌","▋","▊","▉","█"])
      of skLine:
        ("▏", "▁",@[""])
      of skAscii:
        ("|", "=", @["-"])

  if not noHeader:
    styledEcho styleBright, "Ping graph for host ",
      styleUnderscore, fgGreen, host,
      resetStyle, " ",
      fgRed, ipAddr,
      fgDefault, styleBright, " - updated every ",
      fgYellow, $interval,
      fgDefault, " seconds - performing ",
      fgBlue,  if count == 0: "unlimited" else: $count,
      fgDefault, " pings:"

  var
    pingLimit = float.high..float.low
    pingSum = 0.0
    pingCount = 0'u
    packet = PingPacket.init

  let socket = newSocket(sockType = SOCK_RAW, protocol = IPPROTO_ICMP)

  socket.getFd.setSockOptInt(SOL_IP, IP_TTL, 64)

  setControlCHook stop

  while looping:
    inc pingCount

    let startTime = getMonoTime()

    socket.sendTo ipAddr, Port 0, addr packet, sizeof packet

    var
      data, address: string
      port: Port

    if socket.recvFrom(data, sizeof packet, address, port) <= 0:
      echo "Didn't recieve a response"
    else:
      let
        endTime = getMonoTime()
        timeElapsed = endTime - startTime
        ping = timeElapsed.inNanoseconds / 1_000_000

      pingSum += ping
      if ping < pingLimit.a: pingLimit.a = ping
      if ping > pingLimit.b: pingLimit.b = ping

      let
        termWidth = terminalWidth()
        width = if termWidth > leftPad: termWidth - leftPad else: 80
        ratio = ping / maxPing.float
        barString = if ratio < 1:
          let
            cellsPerPing = width.float / maxPing.float
            barsCount = int(cellsPerPing * ping)
            capWidth = (cellsPerPing * ping) - barsCount.float
            capType = int(capWidth * float(halfChars.len + 1))
            capChar = (if capType >= 1: halfChars[capType - 1] else: "")
          barChar.repeat(barsCount) & capChar
        else:
          barChar.repeat(width)

        pingColor = case color
          of ckTruecolor:
            let
              colorRatio = colorCoeff * (ratio - 0.5)
              red = min(int16(255 + colorRatio), 255).uint8
              green = min(255, max(int16(255.0 - colorRatio), desaturation.int16)).uint8
            rgb(red, green, desaturation).ansiForegroundColorCode
          of ck16Color:
            ansiForegroundColorCode(
              if ratio <= 0.33:
                fgGreen
              elif ratio <= 0.67:
                fgYellow
              else:
                fgRed
            )
          of ckNone:
            ""

        timestampString = case timestamp
          of tkShort:
            now().format(shortTimeFormat) & " "
          of tkFull:
            now().format(fullTimeFormat) & " "
          of tkNone:
            ""

      styledEcho timestampString,
        pingColor, ping.formatFloat(ffDecimal, 1).align(5), " ms  ",
        fgDefault, sepChar, " ",
        pingColor, barString

      if count == pingCount: break
      packet = PingPacket.init pingCount.uint16

      sleep max(wait - timeElapsed.inMilliseconds, 0)

  styledEcho styleBright, " Maximum = ",
    fgYellow, $pingLimit.b,
    fgDefault, " ms, Minimum = ",
    fgYellow, $pingLimit.a,
    fgDefault, " ms, Average = ",
    fgYellow, (pingSum / pingCount.float).formatFloat(precision = -1),
    fgDefault, " ms"

clCfg.version = "0.2.0"
dispatch pinggraph,
  short = {"saturation": 'S',"max_ping": 'M',"color": 'C',"no_header": 'H',
      "version": 'v'},
  help = {
    "host": "[host to ping (required)]",
    "interval": "Interval between pings (in seconds).",
    "max_ping": "Maximal visible ping value (in milliseconds).",
    "color": "Color scheme (default based on system capabilities). Available: none, 16color, truecolor.",
    "count": "Number of pings to do. 0 = unlimited.",
    "style": "Bar style. Available: bar, block, line, ascii.",
    "timestamp": "Timestamp type. Available: none, short, full.",
    "saturation": "Saturation of graph with \"truecolor\" colorscheme.",
    "no_header": "Disable header"
  }
