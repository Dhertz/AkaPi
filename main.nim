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
  RED             = rgb(250,45,39)
  PURPLE          = rgb(153,17,153)
  FORECAST_IO     = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"
  MBTA_RED_LINE   = "http://realtime.mbta.com/developer/api/v2/predictionsbystop?api_key=" & MBTA_KEY & "&stop=place-knncl&format=json"
  AKAPI_LOGO_FILE = "AkaPi_logo.ppm"
  FONT_FILE       = "MBTA.ttf"

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
    quit("cannot open: " & fn)

proc loadAkaPiLogo(): PSurface =
  withFile(AkaPiLogo, AKAPI_LOGO_FILE, fmRead):
    if AkaPiLogo.readLine != "P6":
      raise newException(E_base, "Invalid file format")

    var line = ""
    while AkaPiLogo.readLine(line):
      if line[0] != '#':
        break

    if AkaPiLogo.readLine != "255":
      raise newException(E_base, "Invalid file format")

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

proc makePpmFromString(displayString, filename) =
  let
    color = if isPurpleDayz(): PURPLE else: RED
    font = newFont(name = FONT_FILE, size = 16, color = color)

  var
    (textWidth, textHeight) = textBounds(displayString, font)
    surface = newSurface(AKAPI_LOGO.w + textWidth + 15, 18)

  surface.blit((10 + textWidth, 0, AKAPI_LOGO.w, AKAPI_LOGO.h), AKAPI_LOGO, (0, 0, AKAPI_LOGO.w, AKAPI_LOGO.h))
  surface.drawText((5,1), displayString, font)
  withfile(f, filename, fmWrite):
    surface.writePPM(f)

proc writePPM(surface: PSurface, f: File) =
  f.writeln "P6\n", surface.w, " ", surface.h, "\n255"
  for y in 0..surface.h-1:
    for x in 0..surface.w-1:
      var (r, g, b) = surface[(x, y)].extractRGB
      f.write char(r)
      f.write char(g)
      f.write char(b)

template recurringJob(content, displayString, filename, waitTime: int, url, actions: stmt) {.immediate.} =
  var displayString = ""
  block:
    proc asyncJob():Future[int] {.async.} =
      while true:
        let content = try: getContent(url)
               except: "Failed to retrieve URL:\n\t" & getCurrentExceptionMsg()
        try:
           actions
           makePpmFromString(displayString, filename)
        except:
           echo("Failed to create image:\n\t", getCurrentExceptionMsg())

        await sleepAsync(waitTime*1000)
      return 1
    discard asyncJob()

recurringJob(rawWeather, weatherString, "sign_weather.ppm", 600, FORECAST_IO):
  let weather = parseJson(rawWeather)
  weatherString = weather["hourly"]["summary"].str & " Feels like " & $round(weather["currently"]["apparentTemperature"].fnum) & "C"
  weatherString = weatherString.replace("–", by="-")
  var
     now = getLocalTime(getTime())
     bestHour = 0
     bestPrecipProbability = 1.0

  if now.hour < 14:
    for hour in weather["hourly"]["data"]:
      var hourTime = fromSeconds(hour["time"].num).getLocalTime().hour
      if 11 < hourTime and hourtime < 14:
        let bestHourCondition = try: hour["precipProbability"].fnum
                    except: float(hour["precipProbability"].num)
        if bestHourCondition <= bestPrecipProbability:
          bestHour = hourTime
          bestPrecipProbability = bestHourCondition

    if not (bestHour == 14) or not (bestPrecipProbability == 0.0):
      weatherString &= " Probably best to go to lunch around " & $bestHour
  echo(weatherString)

recurringJob(rawRealtime, first_in_direction, "sign_T.ppm", 60, MBTA_RED_LINE):
  let realtime = parseJson(rawRealtime)
  var realtimeSubway: JsonNode
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

  for headsign in seen_headsigns.keys:
    var
      headsignMinutes: seq[string] = @[]
      sortedTimes = seen_headsigns[headsign][0..min(2, len seen_headsigns[headsign])]

    sortedTimes.sort(system.cmp[int])
    for x in sortedTimes:
      headsignMinutes.add($round(x/60))

    first_in_direction &= headsign & " " & join(headsignMinutes, "m, ") & "m $ "
  echo(first_in_direction)

runForever()
