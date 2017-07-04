
# TODO: String formatting. It is gross at the moment
#       Array slices
#       Make sure T returns empty string when no trains available

include secrets

import algorithm
import asyncdispatch
import cgi
import colors
import future
import graphics
import httpclient
import json
import math
import os
import osproc
import sets
import smtp
import streams
import strutils except toLower
import tables
import twitter
import times
import unicode
import xmlparser
import xmltree
import zip/zlib

proc loadAkaPiLogo(): PSurface

const
  RED              = rgb(250, 45,  39)
  GREEN            = rgb(80,  250, 39)
  BLUE             = rgb(40,  90,  229)
  PURPLE           = rgb(153, 17,  153)
  FORECAST_IO      = "https://api.forecast.io/forecast/$KEY/42.364452,-71.089179?units=si" % ["KEY", FORECAST_IO_KEY]
  MBTA_RED_LINE    = "http://realtime.mbta.com/developer/api/v2/predictionsbystop?" &
      "api_key=$KEY&stop=place-knncl&format=json" % ["KEY", MBTA_KEY]
  GOOG_AKAM_STOCK  = "https://www.google.com/async/finance_price_updates?async=lang:en,country:us,rmids:%2Fm%2F07zlcdr"
  EZ_RIDE          = "http://webservices.nextbus.com/service/publicXMLFeed?command=predictions&a=charles-river&stopId=08"
  AKAPI_LOGO_FILE  = "AkaPi_logo.ppm"
  FONT_FILE        = "MBTA.ttf"
  TWILIO_MESSAGES  = "https://api.twilio.com/2010-04-01/Accounts/" & twilioAccount & "/Messages.json"

let AKAPI_LOGO:PSurface = loadAkaPiLogo()

proc isPurpleDaze(now = getLocalTime(getTime())):bool =
#Thurs November 21 - "We don't know why, but we are scared if we change it it will break"
  let
    isPurpleWed = now.weekday == dWed and 3 < now.monthday and now.monthday < 11
    isPurpleThu = now.weekday == dThu and 21 == now.monthday and mNov == now.month
    isPurpleFri = now.weekday == dFri and (now.monthday < 6 or now.monthday > 12)
  isPurpleWed or isPurpleThu or isPurpleFri

template withFile(f, filename, mode, body: untyped): untyped =
  var f: File
  if open(f, filename, mode):
    defer: close(f)
    body
  else:
    raise newException(IOError, "cannot open: " & filename)

proc loadPPM(filename: string): PSurface =
  withFile(AkaPiLogo, filename, fmRead):
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

proc loadAkaPiLogo(): PSurface =
  loadPPM(AKAPI_LOGO_FILE)

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
    result = "$1 and $2" % [bestTime.time.format("htt"), (bestTime.time + oneHour).format("htt")]

template recurringJob(content, displayString, color, filename,
                        waitTime, url, actions: untyped) =
  block:
    proc asyncJob() {.async.} =
      var
        displayString:string
        color:Color
        oldString:string

      while true:
        var content = ""
        let client = newHttpClient()
        try:
          content = client.getContent(url)
        except:
          content = "Failed to retrieve URL: " & url & "\n\t" & getCurrentExceptionMsg()

        client.close()

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
          echo("Failed to create ", filename, ", removing because: \n\t", getCurrentExceptionMsg(), "\n\n\t", content)
          removeFile(filename)

        await sleepAsync(waitTime*1000)
    discard asyncJob()

recurringJob(rawWeather, weatherString, weatherColor, "sign_weather.ppm", 600, FORECAST_IO):
  let
    weather = parseJson(rawWeather)
    feelsLike = try: int round(weather["currently"]["apparentTemperature"].getFNum)
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

  let modes = realtime["mode"]
  if modes == nil:
    raise newException(IOError, "MBTA JSON is not as we expected")

  for mode in modes:
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
           var dest_times = seen_headsigns[trip["trip_headsign"].getStr]
           dest_times.add(secAway)
           seen_headsigns[trip["trip_headsign"].getStr] = dest_times

  var headsigns = lc[x | (x <- seen_headsigns.keys), string]
  headsigns.sort(system.cmp[string])

  for headsign in headsigns:
    var sortedTimes = seen_headsigns[headsign][0..min(1, len(seen_headsigns[headsign])-1)]
    sortedTimes.sort(system.cmp[int])
    let headsignMinutes = lc[($(int round(x/60))) | (x <- sortedTimes), string]
    first_in_direction &=  "$dest ${times}m { " % ["dest", headsign, "times", join(headsignMinutes, "m, ")]

  TColor = if isPurpleDaze(): PURPLE else: RED

  echo first_in_direction

recurringJob(rawStock, stockString, stockColor, "sign_stock.ppm", 180, GOOG_AKAM_STOCK):
  var trimmedStock = rawStock
  if rawStock.startsWith(")]}'"):
    trimmedStock = rawStock.subStr(4)
  let
    stock = parseJson(trimmedStock)
    priceUpdate = stock["PriceUpdates"]["price_update"][0]
    stockSymbol = priceUpdate["symbol"].getStr
    stockPrice = priceUpdate["price"]["formatted_price"]["formatted_value"].getStr
    stockChangeVal = priceUpdate["price"]["formatted_price_change"]["formatted_value"].getStr
    stockChangePos = priceUpdate["price"]["is_price_change_non_negative"].getBVal
  var
    stockString = stockSymbol & ":" & stockPrice

  if stockChangePos:
    stockColor = GREEN
    stockString &= "}" & stockChangeVal
  else:
    stockColor = RED
    stockString &= "|" & stockChangeVal

  echo stockString

recurringJob(first_in_direction, ezString, ezColor, "sign_ez.ppm", 60, EZ_RIDE):
  let ezStream = newStringStream first_in_direction
  ezString = ""
  for direction in ezStream.parseXml.findAll("direction"):
    let unsortedTimes = lc[parseInt(x.attr("minutes")) | (x <- direction.findAll "prediction"), int]

    if unsortedTimes.len == 0: continue
    let sortedTimes = unsortedTimes.sorted(system.cmp[int])[0..min(1, len(unsortedTimes)-1)]

    var strSortedTimes = lc[$x | (x <- sortedTimes), string]
    if strSortedTimes.len > 0:
      ezString &= "$dest: ${times}m" % ["dest", direction.attr("title"), "times", join(strSortedTimes, "m, ")]

  if ezString != "":
    ezString = "EZRide - " & ezString
    echo ezString

  ezColor = if isPurpleDaze(): PURPLE else: BLUE

proc getTwitterStatuses() {.async.} =
  var
    consumerToken = newConsumerToken(twitterAppPubTok, twitterAppPrivTok)
    twitterAPI = newTwitterAPI(consumerToken, twitterOAuthPubKey, twitterOAuthPrivKey)
    oldString = ""
  while true:
    let resp = twitterAPI.mentionsTimeline()
    if resp.status == "200 OK":
      let tweet_json = parseJson(resp.body)
      if tweet_json.len > 0:
        let
          tweet = "@${user}: $tweet" % ["user", tweet_json[0]["user"]["screen_name"].getStr, "tweet", tweet_json[0]["text"].getStr]
          clean_tweet = execProcess("/home/pi/TwitFilter/TwitFilter \"" & tweet.replace("’", by="\'") &
                         '"').strip(trailing=true).replace("&gt;", by=">").replace("&lt;", by="<")

        echo clean_tweet
        let colour = if isPurpleDaze(): PURPLE else: BLUE
        if clean_tweet != oldString:
          oldString = clean_tweet
          makePpmFromString(clean_tweet, colour, "sign_tweet.ppm")
        if clean_tweet == "":
              removeFile("sign_tweet.ppm")

    await sleepAsync(180*1000)

discard getTwitterStatuses()

proc textNumber(client: HttpClient, number:string, message:string) =
  let encodedBody = "To=" & encodeUrl(number) & "&MessagingServiceSid=" & twilioMSid & "&Body=" & encodeUrl(message)
  discard client.postContent(TWILIO_MESSAGES, body=encodedBody)

proc newTwilioHttpClient(): HttpClient =
  let client = newHttpClient(timeout=4000)
  client.headers.add("Authorization", "Basic " & twilioAuth & "\c\L")
  return client

proc manageSubscribers(): seq[string] =
  let
    client = newTwilioHttpClient()
    rawMessages = client.getContent(TWILIO_MESSAGES & "?To=" & encodeUrl(twilioUSNumber))
    messages = parseJson(rawMessages)
  withFile(subs, "subscribers.txt", fmReadWrite):
    var
      currentSubscribers = toSet(readLine(subs).split(","))
      lastSeenMessageId = readline(subs)
      messagesToSend = initTable[string, string]()
    echo "Subscribed to purple daze texts: " & $currentSubscribers
    echo "Last seen text id: " & lastSeenMessageId

    for message in messages["messages"]:
      if message["sid"].getStr == lastSeenMessageId: break
      var
        responseText = ""
        fromNum = message["from"].getStr
      case message["body"].getStr.toLower:
        of "subscribe", "start":
          if not currentSubscribers.contains(fromNum):
            currentSubscribers.incl(fromNum)
            echo "subscribing " & fromNum
            responseText = "Thanks for subscribing to Puple Daze text updates." &
                              " I'll be sure to let you know when to dress up! 💃"
          else:
            responseText = "Woah there eager beaver, looks like you are already on" &
                              " the VIP list! I'll make sure you get special treatment though"
        of "stop", "unsubscribe", "no":
          if currentSubscribers.contains(fromNum):
            currentSubscribers.excl(fromNum)
            echo "unsubscribing " & fromNum
            responseText = "Oh no!, I am sorry to see you go, but I will no " &
                              "longer remind you to encounter the Purple Daze 😔"
          else:
            responseText = "Don't worry, you weren't even included yet." &
                              " I'm not hurt, I didn't like the look of your phone number anyway"
        else:
          echo "weird message: " & fromNum & message["body"].getStr
          responseText = "Hmm. Not quite sure I know what you mean! 🤔  Respond with start" &
                            " to subscribe to notifications of Purple Daze or stop to unsubscribe."
      messagesToSend[fromNum] = responseText

    let currentSubscribersArr = lc[ x | (x <- currentSubscribers.items), string]
    lastSeenMessageId = messages["messages"][0]["sid"].getStr

    writeLine(subs, currentSubscribersArr.join(","))
    writeLine(subs, lastSeenMessageId)

    for number, message in messagesToSend:
      textNumber(client, number, message)

    return currentSubscribersArr

proc emailPurpleDaze() {.async.} =
  while true:
    let
      subscribers = manageSubscribers()
      now = getLocalTime(getTime())
    if now.hour == 17 and isPurpleDaze(now + initInterval(days=1)):
      let msg = createMessage("Purple Daze incoming!", "Remember to wear one of your finest purple garments tomorrow.\n Do you need an extra reminder tomorrow morning? I can send you an SMS! Sign up by texting START to (617) 702-4522", @[purpleEmail])
      var serv = connect(SMTPServer)
      echo("\n" & $msg & "\n")
      serv.sendmail(myEmail, @[purpleEmail], $msg)
    if now.hour == 7 and isPurpleDaze(now):
      for number in subscribers:
        echo "Sending purple daze remider to " & number
        textNumber(newTwilioHttpClient(), number, "Remember it is Purple Daze today!")
    await sleepAsync(3600*1000)

discard emailPurpleDaze()


runForever()
