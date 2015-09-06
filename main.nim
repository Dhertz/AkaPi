# DHertz's raspberry-pi digital signage runner
# TODO: String formatting. It is gross at the moment
#       There must be a way to stop these really long strings being on one line. Right guys? guys??
#       Array slices
#       Make sure T returns empty string when no trains available
#       Use newer Json accessors with defaults

include secrets

import algorithm
import asyncdispatch
import colors
import future
import graphics
import httpclient
import json
import math
import os
import smtp
import streams
import strutils
import tables
import times
import xmlparser
import xmltree

proc loadAkaPiLogo(): PSurface

const
  RED              = rgb(250, 45,  39)
  GREEN            = rgb(80,  250, 39)
  BLUE             = rgb(40,  90,  229)
  PURPLE           = rgb(153, 17,  153)
  FORECAST_IO      = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"
  MBTA_RED_LINE    = "http://realtime.mbta.com/developer/api/v2/predictionsbystop?api_key=" & MBTA_KEY & "&stop=place-knncl&format=json"
  YAHOO_AKAM_STOCK = "https://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20yahoo.finance.quote%20where%20symbol%20%3D%20'AKAM'&format=json&diagnostics=true&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys&callback="
  EZ_RIDE          = "http://webservices.nextbus.com/service/publicXMLFeed?command=predictions&a=charles-river&stopId=08"
  AKAPI_LOGO_FILE  = "AkaPi_logo.ppm"
  FONT_FILE        = "MBTA.ttf"

let AKAPI_LOGO:PSurface = loadAkaPiLogo()

proc isPurpleDaze(now = getLocalTime(getTime())):bool =
#Thurs November 21 - "We don't know why, but we are scared if we change it it will break"
  let
    isPurpleWed = now.weekday == dWed and 3 < now.monthday and now.monthday < 11
    isPurpleThu = now.weekday == dThu and 21 == now.monthday and mNov == now.month
    isPurpleFri = now.weekday == dFri and (now.monthday < 6 or now.monthday > 12)
  isPurpleWed or isPurpleThu or isPurpleFri

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
    if AkaPiLogo.readLine() != "P6":
      raise newException(IOError, "Invalid file format")

    var line = AkaPiLogo.readLine()
    while line[0] == '#':
      line = AkaPiLogo.readLine()

    if AkaPiLogo.readLine != "255":
      raise newException(IOError, "Invalid file format")

    let
      parts = line.split(" ")
      (x, y) = (parseInt parts[0], parseInt parts[1])
    var
      arr: array[256, int8]
      read = AkaPiLogo.readBytes(arr, 0, 255)
      pos = 0

    result = newSurface(x, y)
    while read != 0:
      for i in countup(0, read - 3, 3):
        result[pos mod x, (pos div x) mod y]=rgb(arr[i].uint8, arr[i+1].uint8, arr[i+2].uint8)
        inc pos

      read = AkaPiLogo.readBytes(arr, 0, 255)

proc writePPM(surface: PSurface, f: File) =
  f.writeLine "P6\n", surface.w, " ", surface.h, "\n255"
  for y in 0..surface.h-1:
    for x in 0..surface.w-1:
      var (r, g, b) = surface[(x, y)].extractRGB
      f.write char(r)
      f.write char(g)
      f.write char(b)

proc makePpmFromString(displayString: string, color: Color, filename: string) =
  let
    font = newFont(name = FONT_FILE, size = 16, color = color)
    (textWidth, _) = textBounds(displayString, font)
    surface = newSurface(AKAPI_LOGO.w + textWidth + 15, 18)

  # Put text with 5px margin onto Surface
  surface.drawText((5,1), displayString, font)

  # Put the logo 5px after the end of the text - "block image transfer"
  # proc blit*(destSurf: PSurface, destRect: Rect, srcSurf: PSurface, srcRect: Rect)
  surface.blit((10 + textWidth, 0, AKAPI_LOGO.w, AKAPI_LOGO.h), AKAPI_LOGO, (0, 0, AKAPI_LOGO.w, AKAPI_LOGO.h))

  echo("Saving ", filename)
  withfile(f, filename, fmWrite):
    surface.writePPM(f)

proc whenToLeave(begin, finish: int, weather: JsonNode): string =
  var
    bestTime: tuple[time: TimeInfo, chance: float] = (getLocalTime(getTime()), 1.0)
    forcastTime: TimeInfo
  let
    today = getLocalTime(getTime()).monthday

  for hour in weather["hourly"]["data"]:
    forcastTime = fromSeconds(hour["time"].getNum).getLocalTime()
    if begin <= forcastTime.hour and forcastTime.hour <= finish and forcastTime.monthday == today:
      let bestHourCondition = try: hour["precipProbability"].getFnum
                              except: float(hour["precipProbability"].getNum)
      if bestHourCondition < bestTime.chance:
        bestTime = (forcastTime, bestHourCondition)

  if (bestTime.time.hour != begin or bestTime.chance > 0.1) and bestTime.chance != 1.0:
    let oneHour = initInterval(hours=1)
    result = bestTime.time.format("htt") & " and " & (bestTime.time + oneHour).format("htt")

template recurringJob(content, displayString, color, filename, waitTime: int, url, actions: stmt) {.immediate.} =
  block:
    proc asyncJob():Future[int] {.async.} =
      var
        displayString:string
        color:Color
        oldString:string

      while true:
        let content = try: getContent(url)
                      except: "Failed to retrieve URL:\n\t" & getCurrentExceptionMsg()
        try:
          #Code from template
          actions

          if displayString != oldString:
            oldString = displayString
            if displayString == "":
              removeFile(filename)
            else:
              makePpmFromString(displayString, color, filename)
        except:
          echo("Failed to create " & filename & ":\n\t", getCurrentExceptionMsg())

        await sleepAsync(waitTime*1000)
      return 1
    discard asyncJob()

recurringJob(rawWeather, weatherString, weatherColor, "sign_weather.ppm", 600, FORECAST_IO):
  let
    weather = parseJson(rawWeather)
    feelsLike = try: round(weather["currently"]["apparentTemperature"].getFNum)
                except: int weather["currently"]["apparentTemperature"].getNum

  weatherString = weather["hourly"]["summary"].getStr & " Feels like " & $feelsLike & "C"
  weatherString = weatherString.replace("–", by="-").replace("(").replace(")")

  let now = getLocalTime(getTime())

  if now.hour < 14:
    var bestHour = whenToLeave(11, 14, weather)
    if bestHour != nil:
      weatherString &= ". Probably best to go to lunch between " & bestHour
  elif now.hour < 19:
    var bestHour = whenToLeave(16, 19, weather)
    if bestHour != nil:
      weatherString &= ". Probably best to go home between " & bestHour

  weatherColor = if isPurpleDaze(): PURPLE else: RED

  echo weatherString

recurringJob(rawRealtime, first_in_direction, TColor, "sign_T.ppm", 60, MBTA_RED_LINE):
  let realtime = parseJson(rawRealtime)
  var realtimeSubway: JsonNode

  first_in_direction = ""

  for mode in realtime["mode"]:
    if mode["mode_name"].getStr == "Subway":
      realtimeSubway = mode

  if realtimeSubway == nil:
    raise newException(IOError, "MBTA JSON is not as we expected")

  var seen_headsigns = initOrderedTable[string, seq[int]]()
  # Route = subway line, trip = individual train
  for route in realtimeSubway["route"]:
    for direction in route["direction"]:
      for trip in direction["trip"]:
        var secAway = parseInt(trip["pre_away"].getStr)
        # Skip trains that you couldn't get to from the office
        if 200 >= secAway:
           continue
        # Headsign = destination
        elif not seen_headsigns.hasKey(trip["trip_headsign"].getStr):
           seen_headsigns[trip["trip_headsign"].getStr] = @[secAway]
        else:
           seen_headsigns[trip["trip_headsign"].getStr] = seen_headsigns[trip["trip_headsign"].getStr] & secAway

  var headsigns = lc[x | (x <- seen_headsigns.keys), string]
  headsigns.sort(system.cmp[string])

  for headsign in headsigns:
    var sortedTimes = seen_headsigns[headsign][0..min(1, len(seen_headsigns[headsign])-1)]
    sortedTimes.sort(system.cmp[int])
    let headsignMinutes = lc[($round(x/60)) | (x <- sortedTimes), string]
    first_in_direction &=  headsign & " " & join(headsignMinutes, "m, ") & "m $ "

  TColor = if isPurpleDaze(): PURPLE else: RED

  echo first_in_direction

recurringJob(rawStock, stockString, stockColor, "sign_stock.ppm", 20, YAHOO_AKAM_STOCK):
  let
    stock = parseJson(rawStock)
    stockSymbol = stock["query"]["results"]["quote"]["symbol"].getStr
    stockPrice = parseFloat(stock["query"]["results"]["quote"]["LastTradePriceOnly"].getStr)
  var
    stockString = stockSymbol & ":" & formatFloat(stockPrice, precision = 2, format = ffDecimal)

  var stockChange = try: parseFloat (stock["query"]["results"]["quote"]["Change"].getStr)
                         except: 0.0

  if stockChange < 0:
    stockColor = RED
    stockString &= '%' & formatFloat(stockChange * -1, precision = 2, format = ffDecimal)
  else:
    stockColor = GREEN
    stockString &= '&' & formatFloat(stockChange, precision = 2, format = ffDecimal)

  echo stockString

recurringJob(first_in_direction, ezString, ezColor, "sign_ez.ppm", 60, EZ_RIDE):
  let ezStream = newStringStream first_in_direction
  ezString = ""
  for direction in ezStream.parseXml.findAll("direction"):
    let unsortedTimes = lc[parseInt(x.attr("minutes")) | (x <- direction.findAll "prediction"), int]

    if unsortedTimes.len == 0: continue
    let sortedTimes = unsortedTimes.sorted(system.cmp[int])

    var strSortedTimes = lc[$x | (x <- sortedTimes), string]
    ezString &= direction.attr("title") & ":" & join(strSortedTimes, "m, ") & "m "

  if ezString != "":
    ezString = "EZRide - " & ezString
    echo ezString

  ezColor = if isPurpleDaze(): PURPLE else: BLUE

proc emailPurpleDaze(): Future[void] {.async.} =
  while true:
    let now = getLocalTime(getTime())
    if now.hour == 17 and isPurpleDaze(now + initInterval(days=1)):
      let msg = createMessage("Purple Daze incoming!", "Remember to wear one of your finest purple garments tomorrow.", @[purpleEmail])
      var serv = connect(SMTPServer)
      echo ("\n" & $msg & "\n")
      serv.sendmail(myEmail, @[purpleEmail], $msg)
    await sleepAsync(3600*1000)

discard emailPurpleDaze()

runForever()
