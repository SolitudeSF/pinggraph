import terminal, os, osproc, strutils, math, times, colors
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

proc main(
    hosts: seq[string],
    interval = 0.5,
    maxping = 300'u,
    count = 0'u,
    style = skBar,
    header = true,
    color = (
      case getEnv("COLORTERM")
      of "truecolor", "24bit":
        ckTruecolor
      else:
        ck16Color
    ),
    timestamp = tkNone,
    saturation = 160'u8
  ) =

  if hosts.len == 0:
    stderr.writeLine "Provide host to ping"
    quit 1
  elif hosts.len > 1:
    stderr.writeLine "Ignoring additional hosts"

  var count = count

  let
    host = hosts[0]
    wait = interval * 1000
    desaturation = 255'u8 - saturation
    colorCoeff = 512.0 - desaturation.float * 2.0

    cmd = "ping " & (when defined(windows): "-n" else: "-c") & " 1 " & host

    (barChar, halfChar, sepChar) = (
      case style
      of skBar:
        ("▄", "▖", "▏")
      of skBlock:
        ("█", "▌", "▏")
      of skLine:
        ("▁", "", "▏")
      of skAscii:
        ("=", "-", "|")
    )

  if header:
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

      let
        tWidth = terminalWidth()
        width = uint(if tWidth != 0: tWidth - 12 else: 80)
        pingString = output.splitLines[(when defined(windows): 2 else: 1)].
                              split('=')[^1].split("ms")[0].strip

      ping = pingString.parseFloat

      let
        ratio = ping / maxPing.float
        ratioMinus = ratio - 0.5
        barsCount = uint(ratio * width.float)
        barPing = round(barsCount.float / width.float / ratio * ping)
        barPingNext = round((barsCount + 1).float / width.float / ratio * ping)
        barPingHalf = (barPing + barPingNext) / 2.0
        drawCap = not (maxPing <= width or barsCount >= width)
        cap = (if drawCap and ping >= barPingHalf and ping <= barPingNext:
          halfChar else: "")

        barString = barChar.repeat(min(barsCount, width)) & cap

        pingColor = (
          case color
          of ckTruecolor:
            let red = min(int16(255.0 + colorCoeff * ratioMinus), 255'i16).uint8
            let green = min(255, max(int16(255.0 - colorCoeff * ratioMinus), desaturation.int16)).uint8
            let blue = desaturation
            rgb(red, green, blue).ansiForegroundColorCode
          else:
            ansiForegroundColorCode(
              if ratio >= 0.0 and ratio <= 0.33:
                fgGreen
              elif ratio > 0.33 and ratio <= 0.67:
                fgYellow
              else:
                fgRed
            )
        )

        timestampString = (
          case timestamp
          of tkShort:
            now().format(shortTimeFormat)
          of tkFull:
            now().format(fullTimeFormat)
          of tkNone:
            ""
        )

      styledEcho(
        timestampString, " ",
        pingColor,
        (ping.uint.`$`).align(4), " ms  ",
        fgDefault,
        sepChar, " ",
        pingColor,
        barString
      )

    else:
      stderr.styledWriteLine(fgRed, styleBright, output)

    if count != 0:
      dec count
      if count == 0:
        break

    let sleepTime = int(wait - min(ping, wait))
    sleep sleepTime


dispatch main
