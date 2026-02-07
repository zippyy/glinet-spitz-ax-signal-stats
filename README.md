## GL-iNet Spitz AX X3000/Puli AX XE3000 Signal Stats server

- This is a simple HTTP server that returns an autorefreshing page with CA stats to help when adjusting and positioning the router and antennas to get the best signal.

- I forked this from [rwasef1830](https://github.com/rwasef1830/glinet-spitz-ax-signal-stats) and created an installer that asks for your prefered port, finds the local IP and outputs the url 


## Install (GL.iNet / OpenWrt)

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/zippyy/glinet-spitz-ax-signal-stats/main/install.sh)"
```

## Manual install instructions from the original repo

```sh
- How to setup manually
1. Clone this repo.
2. Upload openwrt/bin/glinet-spitz-ax-signal-stats to /root
3. Upload openwrt/etc/init.d/glinet-spitz-ax-signal-stats to /etc/init.d
4. SSH to the router
5. chmod +x /root/glinet-spitz-ax-signal-stats
6. chmod +x /etc/init.d/glinet-spitz-ax-signal-stats
7. /etc/init.d/glinet-spitz-ax-signal-stats enable
8. /etc/init.d/glinet-spitz-ax-signal-stats start
9. Visit http://router-ip:8080/ default is http://192.168.8.1:8080/
10. Adjust router to get best numbers.
11. Enjoy.
```
-- Do not expose port 8080 in the firewall otherwise the whole world will be able to see your location and signal level. There is no access restriction of any kind. This port should be exposed internally only.
