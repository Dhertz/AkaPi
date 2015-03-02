import asyncdispatch, asyncnet
import httpclient
import json
import math
import strutils

type
    color = tuple[red:int, green:int, blue:int]
const
    RED: color = (250,45,39)
    PURPLE: color = (153,17,153)
    FORECAST_IO: string = "https://api.forecast.io/forecast/" & FORECAST_IO_KEY & "/42.364452,-71.089179?units=si"

template recurringJob(content, waitTime: int, url, actions: stmt) {.immediate.} =
    block:
        proc asyncJob():Future[int] {.async.} =
            while true:
                var content = try: getContent(url)
                          except: "Failed to retrieve URL"
                actions
                await sleepAsync(waitTime*1000)
            return 1
        discard asyncJob()

recurringJob(rawWeather, 10, FORECAST_IO):
    var weather = parseJson(rawWeather)
    var weatherString = weather["hourly"]["summary"].str & " Feels like " & $round(weather["currently"]["apparentTemperature"].fnum) & "C"
    weatherString = weatherString.replace("–", by="-")
    echo weatherString

runForever()
