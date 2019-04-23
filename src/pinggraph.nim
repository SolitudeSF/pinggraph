import terminal, os, osproc, strutils, times, colors
import cligen

type
  TimestampKind = enum
    tkFull = "full", tkShort = "short", tkNone = "none"
  StyleKind = enum
    skBar = "bar", skBlock = "block", skLine = "line", skAscii = "ascii"
  ColorKind = enum
    ck16Color = "16color", ckTruecolor = "truecolor", ckNone = "none"

const
  shortTimeFormat = initTimeFormat("HH:mm:ss")
  fullTimeFormat = initTimeFormat("yyyy-MM-dd HH:mm:ss")

var
  pingMin = float.high
  pingMax, pingSum = 0.0
  pingCount = 0'u

proc doQuit {.noconv.} =
  styledEcho(
    styleBright,
    " Maximum = ",
    fgYellow,
    $pingMax,
    fgDefault,
    " ms, Minimum = ",
    fgYellow,
    $pingMin,
    fgDefault,
    " ms, Average = ",
    fgYellow,
    (pingSum / pingCount.float).formatFloat(precision = -1),
    fgDefault,
    " ms"
  )
  quit 0

proc pinggraph(
    host: seq[string],
    interval = 0.5,
    max_ping = 300'u,
    count = 0'u,
    style = skBlock,
    no_header = false,
    color = (if (enableTrueColors(); isTrueColorSupported()):
      ckTruecolor else: ck16Color),
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
    wait = interval * 1000
    desaturation = 255'u8 - saturation
    colorCoeff = 512.0 - desaturation.float * 2.0

    leftPad = 12 + (
      case timestamp
      of tkNone:
        0
      of tkShort:
        9
      of tkFull:
        20
    )

    cmd = "ping " & (when defined(windows): "-n" else: "-c") & " 1 " & host

    (sepChar, barChar, halfChars) = (
      case style
      of skBar:
        ("▏", "▄", @["▖"])
      of skBlock:
        ("▏", "█", @["▏","▎","▍","▌","▋","▊","▉","█"])
      of skLine:
        ("▏", "▁",@[""])
      of skAscii:
        ("|", "=", @["-"])
    )


  if not noHeader:
    styledEcho(
      styleBright,
      "Ping graph for host ",
      styleUnderscore, fgGreen,
      host,
      resetStyle, styleBright,
      " - updated every ",
      fgYellow,
      $interval,
      fgDefault,
      " seconds - performing ",
      fgBlue,
      (if count == 0: "unlimited" else: $count),
      fgDefault,
      " pings:",
    )

  while true:
    var ping = 0.0
    let (output, errCode) = execCmdEx(cmd)

    if errCode == 0:

      ping = parseFloat(
        when defined(windows):
          let
            lineStartFirst = output.find('\n') + 1
            lineStart = output.find('\n', start = lineStartFirst) + 1
            lineEnd = output.find('\n', start = lineStart)
            firstEq = output.rfind('=', start = lineEnd)
          output[output.rfind('=', start = firstEq - 1) + 1..firstEq - 7]
        else:
          let
            lineStart = output.find('\n') + 1
            lineEnd = output.find('\n', start = lineStart)
          output[output.rfind('=', start = lineEnd) + 1..lineEnd - 4]
      )

      inc pingCount
      pingSum += ping
      if ping > pingMax: pingMax = ping
      if ping < pingMin: pingMin = ping

      let
        tWidth = terminalWidth()
        width = if tWidth > leftPad: tWidth - leftPad else: 80
        ratio = ping / maxPing.float
        barString = (if ratio < 1:
          let
            cellsPerPing = width.float / maxPing.float
            barsCount = int(cellsPerPing * ping)
            capWidth = (cellsPerPing * ping) - barsCount.float
            capType = int(capWidth * float(halfChars.len + 1))
            capChar = (if capType >= 1: halfChars[capType - 1] else: "")
          barChar.repeat(barsCount) & capChar
        else:
          barChar.repeat(width)
        )

        pingColor = (
          case color
          of ckTruecolor:
            let
              ratioMinus = ratio - 0.5
              red = min(int16(255.0 + colorCoeff * ratioMinus), 255'i16).uint8
              green = min(255, max(int16(255.0 - colorCoeff * ratioMinus),
                                   desaturation.int16)).uint8
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
        )
        timestampString = (
          case timestamp
          of tkShort:
            now().format(shortTimeFormat) & " "
          of tkFull:
            now().format(fullTimeFormat) & " "
          of tkNone:
            ""
        )

      styledEcho(
        timestampString,
        pingColor,
        (ping.formatFloat(ffDecimal, 1)).align(5), " ms  ",
        fgDefault,
        sepChar, " ",
        pingColor,
        barString
      )

    else:
      stderr.styledWriteLine(fgRed, styleBright, output)

    if count != 0 and count == pingCount: break

    let sleepTime = int(wait - min(ping, wait))
    sleep sleepTime

  doQuit()


setControlCHook doQuit

dispatch pinggraph,
  version = ("version", "0.1.4"),
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
