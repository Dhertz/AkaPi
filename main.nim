import asyncdispatch
import colors
import graphics
import httpclient
import json
import math
import strutils
import times

const
    RED: Color = rgb(250,45,39)
    PURPLE: Color = rgb(153,17,153)
    FORECAST_IO: string = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"

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

template recurringJob(content, waitTime: int, url, actions: stmt) {.immediate.} =
    block:
        proc asyncJob():Future[int] {.async.} =
            while true:
                let content = try: getContent(url)
                           except: "Failed to retrieve URL"
                actions
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

recurringJob(rawWeather, 10, FORECAST_IO):
    let weather = parseJson(rawWeather)
    var weatherString = weather["hourly"]["summary"].str & " Feels like " & $round(weather["currently"]["apparentTemperature"].fnum) & "C"
    weatherString = weatherString.replace("–", by="-")
    echo(weatherString)
    let color = if isPurpleDayz(): PURPLE else: RED
    let font = newFont(name = "/home/dhertz/Downloads/MBTA.ttf", size = 16, color = color)
    var (textWidth, textHeight) = textBounds(weatherString, font)
    let surface = newSurface(textWidth + 10, 18)
    surface.drawText((5,1), weatherString, font)
    withfile(f, "/home/dhertz/sign_weather.ppm", fmWrite):
        surface.writePPM(f)

#runForever()
