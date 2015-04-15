import nake

const
  sourceName = "main.nim"
  ArmName    = "AkaPi_arm"
  x86Name    = "AkaPi_x86"

task "debug-build", "Build with debug flags in source":
  if shell(nimExe, "c", "-d:ssl", "-d:debug", "-o:" & x86Name, sourceName):
    echo "Success!"

task "x86-build", "Release for x86":
  if shell(nimExe, "c", "-d:ssl", "-d:release", "-o:" & x86Name, sourceName):
    echo "Success!"

task "arm-build", "Release for ARM":
  if shell(nimExe, "c", "-d:ssl", "-d:release", "--cpu:arm", "--os:linux", "-o:" & ArmName, sourceName):
    echo "Success!"

task "arm-deploy", "Deploy to RaspberryPi":
  if shell(nimExe, "c", "-d:ssl", "-d:release", "--cpu:arm", "--os:linux", "-o:" & ArmName, sourceName):
    if shell("scp", ArmName, "pi@raspberrypi:akamai-sign/"):
      echo "Success!"

task "clean", "Remove all binaries":
  shell("rm", ArmName, x86Name, "nakefile")
  shell("find", "-name", "'*.ppm'", "!", "-name", "'AkaPi_logo.ppm'", "-type", "f", "-exec", "rm", "-f", "{}", "+")
  shell("rm", "-r", "nimcache")
