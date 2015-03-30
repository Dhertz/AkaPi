# DHertz's raspberry-pi digital signage runner
# TODO: String formatting. It is gross at the moment
#       Array slices

import algorithm
import asyncdispatch
import colors
import graphics
import httpclient
import json
import math
import strutils
import tables
import times

proc loadAkaPiLogo(): PSurface

const
  RED              = rgb(250,45,39)
  GREEN            = rgb(80, 250, 39)
  PURPLE           = rgb(153,17,153)
  FORECAST_IO      = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"
  MBTA_RED_LINE    = "http://realtime.mbta.com/developer/api/v2/predictionsbystop?api_key=" & MBTA_KEY & "&stop=place-knncl&format=json"
  YAHOO_AKAM_STOCK = "https://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20yahoo.finance.quote%20where%20symbol%20%3D%20'AKAM'&format=json&diagnostics=true&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys&callback="
  AKAPI_LOGO_FILE  = "AkaPi_logo.ppm"
  FONT_FILE        = "MBTA.ttf"

let AKAPI_LOGO:PSurface = loadAkaPiLogo()

proc isPurpleDayz():bool =
  var now = getLocalTime(getTime())
  return (now.weekday == dWed and 3 < now.monthday and now.monthday < 11) or (now.weekday == dFri and (now.monthday < 6 or now.monthday > 12))

template withFile(f: expr, filename: string, mode: FileMode, body: stmt): stmt {.immediate.} =
  let fn = filename
  var f: File
  if open(f, fn, mode):
    defer: close(f)
    body
  else:
    raise newException(IOError, "cannot open: " & fn)

proc loadAkaPiLogo(): PSurface =
  withFile(AkaPiLogo, AKAPI_LOGO_FILE, fmRead):
    if AkaPiLogo.readLine != "P6":
      raise newException(IOError, "Invalid file format")

    var line = ""
    while AkaPiLogo.readLine(line):
      if line[0] != '#':
        break

    if AkaPiLogo.readLine != "255":
      raise newException(IOError, "Invalid file format")

    var
      parts = line.split(" ")
      (x, y) = (parseInt parts[0], parseInt parts[1])
      result = newSurface(x, y)
      arr: array[256, int8]
      read = AkaPiLogo.readBytes(arr, 0, 255)
      pos = 0

    while read != 0:
      for i in countup(0, read - 3, 3):
        result[pos mod x, (pos div x) mod y]=rgb(arr[i].uint8, arr[i+1].uint8, arr[i+2].uint8)
        inc pos

      read = AkaPiLogo.readBytes(arr, 0, 255)

    return result

proc writePPM(surface: PSurface, f: File) =
  f.writeln "P6\n", surface.w, " ", surface.h, "\n255"
  for y in 0..surface.h-1:
    for x in 0..surface.w-1:
      var (r, g, b) = surface[(x, y)].extractRGB
      f.write char(r)
      f.write char(g)
      f.write char(b)

proc makePpmFromString(displayString: string, color: Color, filename: string) =
  let font = newFont(name = FONT_FILE, size = 16, color = color)
  var
    (textWidth, textHeight) = textBounds(displayString, font)
    surface = newSurface(AKAPI_LOGO.w + textWidth + 15, 18)

  surface.blit((10 + textWidth, 0, AKAPI_LOGO.w, AKAPI_LOGO.h), AKAPI_LOGO, (0, 0, AKAPI_LOGO.w, AKAPI_LOGO.h))
  surface.drawText((5,1), displayString, font)
  echo("Saving ", filename)
  withfile(f, filename, fmWrite):
    surface.writePPM(f)

proc whenToLeave(begin, finish: int, weather: JsonNode): auto =
  var result: tuple[hour: string, chance: float] = ("", 1.0)
  let today = getLocalTime(getTime()).monthday
  for hour in weather["hourly"]["data"]:
    var forcastTime = fromSeconds(hour["time"].num).getLocalTime()
    if begin <= forcastTime.hour and forcastTime.hour <= finish and forcastTime.monthday == today:
      let bestHourCondition = try: hour["precipProbability"].fnum
                              except: float(hour["precipProbability"].num)
      if bestHourCondition <= result.chance:
        result = (forcastTime.format("htt"), bestHourCondition)
  return result

template recurringJob(content, displayString, color, filename, waitTime: int, url, actions: stmt) {.immediate.} =
  block:
    proc asyncJob():Future[int] {.async.} =
      var
        displayString = ""
        color:Color
        oldString = ""

      while true:
        let content = try: getContent(url)
                      except: "Failed to retrieve URL:\n\t" & getCurrentExceptionMsg()
        try:
          actions
          if displayString != oldString:
            oldString = displayString
            makePpmFromString(displayString, color, filename)
        except:
          echo("Failed to create image:\n\t", getCurrentExceptionMsg())

        await sleepAsync(waitTime*1000)
      return 1
    discard asyncJob()

recurringJob(rawWeather, weatherString, weatherColor, "sign_weather.ppm", 600, FORECAST_IO):
  let weather = parseJson(rawWeather)
  weatherString = weather["hourly"]["summary"].str & " Feels like " & $round(weather["currently"]["apparentTemperature"].fnum) & "C"
  weatherString = weatherString.replace("–", by="-").replace("(").replace(")")
  var
    now = getLocalTime(getTime())
    bestHour: tuple[hour: string, chance: float]

  if now.hour < 14:
    bestHour = whenToLeave(11, 14, weather)
    if not (bestHour.hour == "2pm") or not (bestHour.chance == 0):
      let timeStr = if now.format("htt") == bestHour.hour: "now" else: bestHour.hour
      weatherString &= ". Probably best to go to lunch around " & timeStr
  elif now.hour < 19:
    bestHour = whenToLeave(16, 19, weather)
    if not (bestHour.hour == "7pm") or not (bestHour.chance == 0):
      let timeStr = if now.format("htt") == bestHour.hour: "now" else: bestHour.hour
      weatherString &= ". Probably best to go home around " & timeStr

  weatherColor = if isPurpleDayz(): PURPLE else: RED

  echo weatherString

recurringJob(rawRealtime, first_in_direction, TColor, "sign_T.ppm", 60, MBTA_RED_LINE):
  let realtime = parseJson(rawRealtime)
  var realtimeSubway: JsonNode

  first_in_direction = ""

  for mode in realtime["mode"]:
    if mode["mode_name"].str == "Subway":
      realtimeSubway = mode

  if realtimeSubway == nil:
    raise newException(IOError, "MBTA JSON is not as we expected")

  var seen_headsigns = initOrderedTable[string, seq[int]]()
  for route in realtimeSubway["route"]:
    for direction in route["direction"]:
      for trip in direction["trip"]:
        var secAway = parseInt(trip["pre_away"].str)
        if 200 >= secAway:
           continue
        elif not seen_headsigns.hasKey(trip["trip_headsign"].str):
           seen_headsigns[trip["trip_headsign"].str] = @[secAway]
        else:
           seen_headsigns[trip["trip_headsign"].str] = seen_headsigns[trip["trip_headsign"].str] & secAway

  var headsigns: seq[string] = @[]
  for headsign in seen_headsigns.keys:
    headsigns.add(headsign)

  headSigns.sort(system.cmp[string])

  for headsign in headSigns:
    var
      headsignMinutes: seq[string] = @[]
      sortedTimes = seen_headsigns[headsign][0..min(1, len seen_headsigns[headsign])]

    sortedTimes.sort(system.cmp[int])
    for x in sortedTimes :
      headsignMinutes.add($round(x/60))

    first_in_direction &=  headsign & " " & join(headsignMinutes, "m, ") & "m $ "

  TColor = if isPurpleDayz(): PURPLE else: RED

  echo first_in_direction

recurringJob(rawStock, stockString, stockColor, "sign_stock.ppm", 20, YAHOO_AKAM_STOCK):
  let stock = parseJson(rawStock)
  stockString = stock["query"]["results"]["quote"]["symbol"].str & ":" & stock["query"]["results"]["quote"]["LastTradePriceOnly"].str

  let stockChange = parseFloat stock["query"]["results"]["quote"]["Change"].str

  if  stockChange <= 0:
    stockColor = RED
    stockString &= '%' & formatFloat(stockChange, precision = 2)
  else:
    stockColor = GREEN
    stockString &= '&' & formatFloat(stockChange, precision = 2)

  echo stockString


runForever()
