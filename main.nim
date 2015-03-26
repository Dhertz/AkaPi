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

const
    RED = rgb(250,45,39)
    PURPLE = rgb(153,17,153)
    FORECAST_IO = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"
    MBTA_RED_LINE = "http://realtime.mbta.com/developer/api/v2/predictionsbystop?api_key=" & MBTA_KEY & "&stop=place-knncl&format=json"

proc writePPM(surface: PSurface, f: File) =
    f.writeln "P6\n", surface.w, " ", surface.h, "\n255"
    for y in 0..surface.h-1:
        for x in 0..surface.w-1:
           var (r, g, b) = surface[(x, y)].extractRGB
           f.write char(r)
           f.write char(g)
           f.write char(b)

proc isPurpleDayz():bool =
    var now = getLocalTime(getTime())
    return (now.weekday == dWed and 3 < now.monthday and now.monthday < 11) or (now.weekday == dFri and (now.monthday < 6 or now.monthday > 12))

template recurringJob(content, displayString, filename, waitTime: int, url, actions: stmt) {.immediate.} =
    var displayString = ""
    block:
        proc asyncJob():Future[int] {.async.} =
            while true:
                let content = try: getContent(url)
                           except: "Failed to retrieve URL"
                try: actions
                except: echo("Failed to create image")
               
                let color = if isPurpleDayz(): PURPLE else: RED
                let font = newFont(name = "/home/dhertz/Downloads/MBTA.ttf", size = 16, color = color)
                var (textWidth, textHeight) = textBounds(displayString, font)
                let surface = newSurface(textWidth + 10, 18)
                surface.drawText((5,1), displayString, font)
                withfile(f, filename, fmWrite):
                    surface.writePPM(f)
 
                await sleepAsync(waitTime*1000)
            return 1
        discard asyncJob()

template withFile(f: expr, filename: string, mode: FileMode, body: stmt): stmt {.immediate.} =
  let fn = filename
  var f: File
  if open(f, fn, mode):
    try:
      body
    finally:
      close(f)
  else:
    quit("cannot open: " & fn)

recurringJob(rawWeather, weatherString, "sign_weather.ppm", 600, FORECAST_IO):
    let weather = parseJson(rawWeather)
    weatherString = weather["hourly"]["summary"].str & " Feels like " & $round(weather["currently"]["apparentTemperature"].fnum) & "C"
    weatherString = weatherString.replace("–", by="-")
    echo(weatherString)

recurringJob(rawRealtime, first_in_direction, "sign_T.ppm", 60, MBTA_RED_LINE):
    let realtime = parseJson(rawRealtime)
    var realtimeSubway: JsonNode
    for mode in realtime["mode"]:
        if mode["mode_name"].str == "Subway":
            realtimeSubway = mode
            break

    first_in_direction = ""
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
        var headsignMinutes: seq[string] = @[]
        var sortedTimes = seen_headsigns[headsign][0..2]
        sortedTimes.sort(system.cmp[int])
        for x in sortedTimes:
            headsignMinutes.add($round(x/60))

        first_in_direction &= headsign & " " & join(headsignMinutes, "m, ") & "m $ "

    echo(first_in_direction)

#runForever()
