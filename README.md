AkaPi is a 16x256 RGB LED display running of a Raspberry Pi 2 model B.
Currently it scrolls multiple images created by different scripts
querying web APIs.

Technical Detail
----------------

The display is actually made up of 8 [Adafruit 16x32 LED Matrices] daisy
chained together, all running off two five-volt ten-amp power supplies
(they can draw a lot when on bright white apparently, though I have not
tested it).
 
It is made up of two distinct parts:

There is low level interface to output values to the displays via the
Raspberry Pi's GPIO and the [RPi-RGB-LED-Matrix] library, with a custom
drawing engine on top. If you are interested in how the displays work, I
suggest starting [here]. This part reads in the simple images and
manages the scrolling and updating the images in memory. It also updates
the animations (see below) to the next frame.

Also, we have a daemon written in [Nim] to generate simple [PPM] images
(basically a large matrix with rgb values for each pixel) with new data
from different web apis on the Raspberry Pi.

### Why *insert immature fashionable language*?

I chose to use nim because I wanted to use one of these [fancy][]
[new][] [compiled] languages, but really like writing Python. Nim seemed
to be the best way to satisfy both of these, as well as produce a
(hopefully) faster binary than running multiple python scripts at once.
Nim also is strongly typed, but has type inference, which is really
cool. I really like the super powerful macro/templating that I can do,
as I made a template to create threads that act on a document fetched
from a URL repeatedly.

```nim
 template recurringJob(content, waitTime: int, url, actions: stmt) {.immediate.} =
   block:
     proc asyncJob():Future[void] {.async.} =
       while true:
         let content = try: getContent(url)
                       except: "Failed to retrieve URL:\n\t" & getCurrentExceptionMsg()
         try:
           actions
         except:
           echo("Failed to run actions:\n\t", getCurrentExceptionMsg())
 
         await sleepAsync(waitTime*1000)
 
     asyncJob()
```

Which would then be called like:

```nim
 recurringJob(document, 600, "http://example.com"):
   let json = parseJson document
   echo json["key"]
```

Nim also allows for me to really easily create a cross compilation
toolchain for the Pi, so I can make compilation very quick for ARM
compared to compiling natively.

Compiling the code
------------------

### Nim
To compile the Nim, you need to have a secrets.nim in the same directory as main.nim. This is not included in the repo as these secrets should not be public.

Here is mine without the tokens:
```nim
const
  FORECAST_IO_KEY     = "xxxxxxxxxxxxxxxxxxxxx"
  MBTA_KEY            = "xxxxxxxxxxxxxxxxxxxxx"
  purpleEmail         = "recipient@example.com"
  myEmail             = "sender@example.com"
  SMTPServer          = "smtp.example.com"
```

You will then need to download and install [nim][3] (the compiler) and [nimble][] (the package manager) to get the required dependencies and install your platform's SDL1 developement package.

Finally, run `nimble install` to install the dependencies and `nake x86-build` to produce the binary. 

### C/C++
To compile the C++ you should just need to cd into the c_src directory and run `make`.

Current information displayed
-----------------------------

-   The AkaPi Logo
-   Next Trains at Kendall T stop
-   Next EZRide buses from outside 8CC (afternoons only)
-   Current stock price and performance
-   Weather for the next few hours and when to leave for lunch/home
    based on chance of precipitation.
-   Purple dayz
-   Email reminders the day before purple dayz

Animations
----------

Animations are made up of multiple frames (ppm images) named 0.ppm,
1.ppm, etc stored in the animations/`$ANIMATION_NAME` directory.
There can also be a file inside the directory named `animate.conf` 
that contains the number of milliseconds each frame should be shown 
for. The format of the file is

`frame_pause $NUMBER_OF_MILLISECONDS`

this should be the first line of the file as all other lines are
discarded. If there is no `animate.conf` present or it cannot be
parsed, a default of 100ms (10 frames per second) is used.

Example animation directories can be found [here][1].

The animations loop and scroll across the display like the other images,
but, unlike the static images, animations are not updated while the
program is running.

### Current Animations

-   Pac Man being chased by ghosts - [source]
-   [Nyan Cat] - [source][2]

Previous information displayed
------------------------------

-   District and Circle Line trains out of South Kensington station
-   Superbowl XLIX average point spread, as reported by [ESPN]
-   [2015][] [Ashes] Test Series scores (Cricket scores for England
    vs Australia)

Wishlist
--------

-   Quote/Fact/Lie/Joke of the day
-   Add notifications to scroll down from the top
-   WebUI

To Do
-----

### C

-   Fix so it doesn't leak like a sieve
-   Find annoying crash
-   Fix cutting lines of the beginning of images
-   Removal of images from hash
-   Refactor animation code into functions
-   Alphabetise includes

### Nim

-   Cache
    -   more - I already save the previous string, and we do not update
        the sign if they are the same
-   Make prettier (output and code)
-   Make weather more concise

  [1]: https://github.com/Dhertz/AkaPi/tree/master/animations
  [2]: http://ledseq.com/forums/topic/nyan-cat/
  [3]: http://nim-lang.org/download.html
  [2015]: https://en.wikipedia.org/wiki/2015_Ashes_series
  [Adafruit 16x32 LED Matrices]: http://www.adafruit.com/product/420
  [Ashes]: https://en.wikipedia.org/wiki/The_Ashes
  [compiled]: http://dlang.org
  [ESPN]: http://espn.go.com/nfl/lines
  [fancy]: http://golang.org
  [github repo]: https://github.com/dhertz/AkaPi
  [here]: https://trmm.net/Octoscroller#Interface
  [new]: http://playrust.com
  [Nim]: http://nim-lang.org
  [nimble]: https://github.com/nim-lang/nimble#installation
  [Nyan Cat]: https://www.youtube.com/watch?v=QH2-TGUlwu4
  [PPM]: http://en.wikipedia.org/wiki/Netpbm_format
  [RPi-RGB-LED-Matrix]: https://github.com/hzeller/rpi-rgb-led-matrix
  [source]: http://ledseq.com/forums/topic/a-few-animations-from-classic-8-bit-games/
